/*
 * godot_weather.cpp — Rain and snow particle system manager.
 *
 * Creates and manages Godot GPUParticles3D nodes for rain and snow
 * effects.  The weather state is read from the engine via a C accessor
 * (godot_weather_accessors.c).
 *
 * Rain: vertical lines with fast downward velocity, short lifetime.
 * Snow: drifting quad particles with slow downward velocity, longer lifetime.
 *
 * The particle volume follows the camera position each frame so that
 * weather is always visible around the player.
 */

#include "godot_weather.h"

#include <godot_cpp/classes/gpu_particles3d.hpp>
#include <godot_cpp/classes/particle_process_material.hpp>
#include <godot_cpp/classes/standard_material3d.hpp>
#include <godot_cpp/classes/base_material3d.hpp>
#include <godot_cpp/classes/quad_mesh.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/color.hpp>

using namespace godot;

/* ── Static state ── */
static GPUParticles3D *s_rain_emitter  = nullptr;
static GPUParticles3D *s_snow_emitter  = nullptr;
static Node3D         *s_weather_root  = nullptr;
static int             s_current_state = 0;  /* WEATHER_NONE */

/* ── Volume dimensions (Godot units = metres) ── */
static constexpr float WEATHER_VOLUME_WIDTH  = 30.0f;  /* ±15m around camera */
static constexpr float WEATHER_VOLUME_HEIGHT = 20.0f;  /* 20m tall column */

/* ===================================================================
 *  Create a rain particle emitter
 * ================================================================ */
static GPUParticles3D *create_rain_emitter(Node3D *parent) {
    GPUParticles3D *rain = memnew(GPUParticles3D);
    rain->set_name("WeatherRain");

    rain->set_amount(2000);
    rain->set_lifetime(1.0);
    rain->set_one_shot(false);
    rain->set_visibility_aabb(AABB(
        Vector3(-WEATHER_VOLUME_WIDTH, -WEATHER_VOLUME_HEIGHT, -WEATHER_VOLUME_WIDTH),
        Vector3(WEATHER_VOLUME_WIDTH * 2, WEATHER_VOLUME_HEIGHT * 2, WEATHER_VOLUME_WIDTH * 2)));

    /* Process material — gravity-driven downward particles */
    Ref<ParticleProcessMaterial> mat;
    mat.instantiate();
    mat->set_direction(Vector3(0.0f, -1.0f, 0.0f));
    mat->set_spread(5.0f);
    mat->set_param_min(ParticleProcessMaterial::PARAM_INITIAL_LINEAR_VELOCITY, 8.0f);
    mat->set_param_max(ParticleProcessMaterial::PARAM_INITIAL_LINEAR_VELOCITY, 12.0f);
    mat->set_gravity(Vector3(0.0f, -9.8f, 0.0f));

    /* Emission box covering the volume */
    mat->set_emission_shape(ParticleProcessMaterial::EMISSION_SHAPE_BOX);
    mat->set_emission_box_extents(
        Vector3(WEATHER_VOLUME_WIDTH * 0.5f, 1.0f, WEATHER_VOLUME_WIDTH * 0.5f));

    rain->set_process_material(mat);

    /* Draw pass: thin stretched quad for rain streaks */
    Ref<QuadMesh> draw_mesh;
    draw_mesh.instantiate();
    draw_mesh->set_size(Vector2(0.02f, 0.4f));

    Ref<StandardMaterial3D> draw_mat;
    draw_mat.instantiate();
    draw_mat->set_transparency(BaseMaterial3D::TRANSPARENCY_ALPHA);
    draw_mat->set_albedo(Color(0.7f, 0.75f, 0.85f, 0.4f));
    draw_mat->set_shading_mode(BaseMaterial3D::SHADING_MODE_UNSHADED);
    draw_mat->set_billboard_mode(BaseMaterial3D::BILLBOARD_PARTICLES);
    draw_mat->set_flag(BaseMaterial3D::FLAG_DISABLE_DEPTH_TEST, false);
    draw_mesh->set_material(draw_mat);

    rain->set_draw_pass_mesh(0, draw_mesh);

    rain->set_emitting(false);
    parent->add_child(rain);
    return rain;
}

/* ===================================================================
 *  Create a snow particle emitter
 * ================================================================ */
static GPUParticles3D *create_snow_emitter(Node3D *parent) {
    GPUParticles3D *snow = memnew(GPUParticles3D);
    snow->set_name("WeatherSnow");

    snow->set_amount(1500);
    snow->set_lifetime(3.0);
    snow->set_one_shot(false);
    snow->set_visibility_aabb(AABB(
        Vector3(-WEATHER_VOLUME_WIDTH, -WEATHER_VOLUME_HEIGHT, -WEATHER_VOLUME_WIDTH),
        Vector3(WEATHER_VOLUME_WIDTH * 2, WEATHER_VOLUME_HEIGHT * 2, WEATHER_VOLUME_WIDTH * 2)));

    /* Process material — slow drifting downward */
    Ref<ParticleProcessMaterial> mat;
    mat.instantiate();
    mat->set_direction(Vector3(0.0f, -1.0f, 0.0f));
    mat->set_spread(30.0f);
    mat->set_param_min(ParticleProcessMaterial::PARAM_INITIAL_LINEAR_VELOCITY, 1.0f);
    mat->set_param_max(ParticleProcessMaterial::PARAM_INITIAL_LINEAR_VELOCITY, 2.5f);
    mat->set_gravity(Vector3(0.3f, -1.5f, 0.2f));

    /* Emission box */
    mat->set_emission_shape(ParticleProcessMaterial::EMISSION_SHAPE_BOX);
    mat->set_emission_box_extents(
        Vector3(WEATHER_VOLUME_WIDTH * 0.5f, 1.0f, WEATHER_VOLUME_WIDTH * 0.5f));

    snow->set_process_material(mat);

    /* Draw pass: small white quad for snowflakes */
    Ref<QuadMesh> draw_mesh;
    draw_mesh.instantiate();
    draw_mesh->set_size(Vector2(0.06f, 0.06f));

    Ref<StandardMaterial3D> draw_mat;
    draw_mat.instantiate();
    draw_mat->set_transparency(BaseMaterial3D::TRANSPARENCY_ALPHA);
    draw_mat->set_albedo(Color(0.95f, 0.95f, 1.0f, 0.7f));
    draw_mat->set_shading_mode(BaseMaterial3D::SHADING_MODE_UNSHADED);
    draw_mat->set_billboard_mode(BaseMaterial3D::BILLBOARD_PARTICLES);
    draw_mat->set_flag(BaseMaterial3D::FLAG_DISABLE_DEPTH_TEST, false);
    draw_mesh->set_material(draw_mat);

    snow->set_draw_pass_mesh(0, draw_mesh);

    snow->set_emitting(false);
    parent->add_child(snow);
    return snow;
}

/* ===================================================================
 *  Public API
 * ================================================================ */

void Godot_Weather_Init(Node3D *parent) {
    if (!parent) return;

    /* Clean up previous weather state */
    Godot_Weather_Shutdown();

    s_weather_root = parent;
    s_rain_emitter = create_rain_emitter(parent);
    s_snow_emitter = create_snow_emitter(parent);
    s_current_state = WEATHER_NONE;

    UtilityFunctions::print("[Weather] Initialised rain and snow emitters.");
}

void Godot_Weather_Update(const Vector3 &camera_pos, float delta) {
    (void)delta;

    int state = Godot_Weather_GetState();
    float density = Godot_Weather_GetDensity();

    /* Reposition emitter volume above the camera */
    Vector3 emitter_pos = camera_pos + Vector3(0.0f, WEATHER_VOLUME_HEIGHT * 0.5f, 0.0f);

    if (s_rain_emitter) {
        s_rain_emitter->set_global_position(emitter_pos);
        bool want_rain = (state == WEATHER_RAIN && density > 0.001f);
        if (want_rain != s_rain_emitter->is_emitting()) {
            s_rain_emitter->set_emitting(want_rain);
            if (want_rain) {
                int amount = (int)(2000.0f * density);
                if (amount < 100) amount = 100;
                s_rain_emitter->set_amount(amount);
            }
        }
    }

    if (s_snow_emitter) {
        s_snow_emitter->set_global_position(emitter_pos);
        bool want_snow = (state == WEATHER_SNOW && density > 0.001f);
        if (want_snow != s_snow_emitter->is_emitting()) {
            s_snow_emitter->set_emitting(want_snow);
            if (want_snow) {
                int amount = (int)(1500.0f * density);
                if (amount < 100) amount = 100;
                s_snow_emitter->set_amount(amount);
            }
        }
    }

    s_current_state = state;
}

void Godot_Weather_Shutdown(void) {
    if (s_rain_emitter) {
        s_rain_emitter->set_emitting(false);
        if (s_rain_emitter->get_parent()) {
            s_rain_emitter->get_parent()->remove_child(s_rain_emitter);
        }
        memdelete(s_rain_emitter);
        s_rain_emitter = nullptr;
    }
    if (s_snow_emitter) {
        s_snow_emitter->set_emitting(false);
        if (s_snow_emitter->get_parent()) {
            s_snow_emitter->get_parent()->remove_child(s_snow_emitter);
        }
        memdelete(s_snow_emitter);
        s_snow_emitter = nullptr;
    }
    s_weather_root = nullptr;
    s_current_state = WEATHER_NONE;
}

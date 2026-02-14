/*
 * godot_frustum_cull.cpp — Camera frustum culling helpers.
 *
 * Phase 258: Extracts the six frustum planes from a Camera3D's combined
 * view-projection matrix and provides AABB / sphere visibility tests.
 */

#include "godot_frustum_cull.h"

#include <godot_cpp/variant/projection.hpp>
#include <godot_cpp/variant/transform3d.hpp>

using namespace godot;

/* ── Internal state ── */

static Plane s_planes[6];   /* L, R, B, T, Near, Far */
static bool  s_valid = false;
static int   s_tested = 0;
static int   s_culled = 0;

/* ===================================================================
 *  Init / Shutdown
 * ================================================================ */

void Godot_FrustumCull_Init(void)
{
    for (int i = 0; i < 6; i++) {
        s_planes[i] = Plane();
    }
    s_valid  = false;
    s_tested = 0;
    s_culled = 0;
}

void Godot_FrustumCull_Shutdown(void)
{
    s_valid  = false;
    s_tested = 0;
    s_culled = 0;
}

/* ===================================================================
 *  Frustum plane extraction
 *
 *  Given the combined view-projection matrix M (column-major as Godot
 *  stores it), the six frustum planes are:
 *
 *    Left   = row3 + row0
 *    Right  = row3 - row0
 *    Bottom = row3 + row1
 *    Top    = row3 - row1
 *    Near   = row3 + row2
 *    Far    = row3 - row2
 *
 *  Each "row" is extracted from the columns of the Projection matrix.
 *  Planes are normalised so that distance tests return true metric
 *  signed distances.
 * ================================================================ */

static inline Plane make_plane(real_t a, real_t b, real_t c, real_t d)
{
    Vector3 n(a, b, c);
    real_t  len = n.length();
    if (len > 1e-6f) {
        real_t inv = 1.0f / len;
        return Plane(n * inv, d * inv);
    }
    return Plane(Vector3(0, 1, 0), 0);
}

void Godot_FrustumCull_UpdateCamera(Camera3D *camera)
{
    /* Reset per-frame stats. */
    s_tested = 0;
    s_culled = 0;

    if (!camera) {
        s_valid = false;
        return;
    }

    /*
     * Build the combined view-projection matrix.
     *
     * Godot's Projection (4×4) is column-major.  We access columns via
     * operator[], where each column is a Vector4.
     *
     * Camera3D::get_camera_projection() returns the projection matrix.
     * The view matrix is the inverse of the camera's global transform.
     */
    Projection proj  = camera->get_camera_projection();
    Transform3D view = camera->get_global_transform().affine_inverse();

    /*
     * Convert the Transform3D (3×4) to a Projection (4×4).
     * Godot's Projection stores columns: columns[0..3], each Vector4.
     */
    Projection view_mat;
    view_mat.columns[0] = Vector4(view.basis[0][0], view.basis[1][0], view.basis[2][0], 0.0f);
    view_mat.columns[1] = Vector4(view.basis[0][1], view.basis[1][1], view.basis[2][1], 0.0f);
    view_mat.columns[2] = Vector4(view.basis[0][2], view.basis[1][2], view.basis[2][2], 0.0f);
    view_mat.columns[3] = Vector4(view.origin.x, view.origin.y, view.origin.z, 1.0f);

    /* Multiply: vp = proj * view_mat.  Projection * Projection is defined. */
    Projection vp = proj * view_mat;

    /*
     * Extract planes.  Godot Projection columns[c] is a Vector4 with
     * components x,y,z,w.  We need "rows" of the 4×4 matrix.
     *
     * Row i component j = columns[j][i].
     */
    #define M(row, col) vp.columns[col][row]

    /* Left:   row3 + row0 */
    s_planes[0] = make_plane(M(3,0) + M(0,0),
                             M(3,1) + M(0,1),
                             M(3,2) + M(0,2),
                             M(3,3) + M(0,3));
    /* Right:  row3 - row0 */
    s_planes[1] = make_plane(M(3,0) - M(0,0),
                             M(3,1) - M(0,1),
                             M(3,2) - M(0,2),
                             M(3,3) - M(0,3));
    /* Bottom: row3 + row1 */
    s_planes[2] = make_plane(M(3,0) + M(1,0),
                             M(3,1) + M(1,1),
                             M(3,2) + M(1,2),
                             M(3,3) + M(1,3));
    /* Top:    row3 - row1 */
    s_planes[3] = make_plane(M(3,0) - M(1,0),
                             M(3,1) - M(1,1),
                             M(3,2) - M(1,2),
                             M(3,3) - M(1,3));
    /* Near:   row3 + row2 */
    s_planes[4] = make_plane(M(3,0) + M(2,0),
                             M(3,1) + M(2,1),
                             M(3,2) + M(2,2),
                             M(3,3) + M(2,3));
    /* Far:    row3 - row2 */
    s_planes[5] = make_plane(M(3,0) - M(2,0),
                             M(3,1) - M(2,1),
                             M(3,2) - M(2,2),
                             M(3,3) - M(2,3));

    #undef M

    s_valid = true;
}

/* ===================================================================
 *  AABB test — "p-vertex" method
 *
 *  For each plane, compute the "positive vertex" (the corner of the
 *  AABB furthest in the direction of the plane normal).  If that vertex
 *  is behind the plane (signed distance < 0) the AABB is entirely
 *  outside.
 * ================================================================ */

bool Godot_FrustumCull_TestAABB(const AABB &bounds)
{
    s_tested++;

    if (!s_valid) {
        return true;  /* No frustum → assume visible. */
    }

    Vector3 min_pt = bounds.position;
    Vector3 max_pt = bounds.position + bounds.size;

    for (int i = 0; i < 6; i++) {
        const Vector3 &n = s_planes[i].normal;
        real_t         d = s_planes[i].d;

        /* Positive vertex: for each axis, pick max if normal > 0, min otherwise. */
        Vector3 p_vertex(
            (n.x >= 0.0f) ? max_pt.x : min_pt.x,
            (n.y >= 0.0f) ? max_pt.y : min_pt.y,
            (n.z >= 0.0f) ? max_pt.z : min_pt.z
        );

        /* Signed distance = dot(normal, vertex) + d.
         * Godot's Plane stores: normal · X = d  (point on plane satisfies this).
         * distance_to(point) = normal.dot(point) - d.
         * If distance_to(p_vertex) < 0, the p-vertex is behind the plane. */
        if (s_planes[i].distance_to(p_vertex) < 0.0f) {
            s_culled++;
            return false;
        }
    }

    return true;
}

/* ===================================================================
 *  Sphere test
 * ================================================================ */

bool Godot_FrustumCull_TestSphere(const Vector3 &center, float radius)
{
    s_tested++;

    if (!s_valid) {
        return true;
    }

    for (int i = 0; i < 6; i++) {
        if (s_planes[i].distance_to(center) < -radius) {
            s_culled++;
            return false;
        }
    }

    return true;
}

/* ===================================================================
 *  Stats
 * ================================================================ */

void Godot_FrustumCull_GetStats(int *tested, int *culled)
{
    if (tested) *tested = s_tested;
    if (culled) *culled = s_culled;
}

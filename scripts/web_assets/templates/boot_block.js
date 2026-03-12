/* MOHAA_BOOT_START */
		/* MOHAAjs: Game Selector + Per-Game Cache + Local File Loader */
		(async function mohaaBoot() {
			var DB_VER = 1, ST = 'f';
			var GAME_DIRS = {0: 'main', 1: 'mainta', 2: 'maintt'};
			var GAME_NAMES = {0: 'Allied Assault', 1: 'Spearhead', 2: 'Breakthrough'};
			var GAME_DEPS = {0: ['main'], 1: ['main', 'mainta'], 2: ['main', 'maintt']};
			var targetGame = 0;
			window.__mohaaTargetGame = 0;

			var urlParams = new URLSearchParams(window.location.search);
			var urlTG = urlParams.get('com_target_game');
			if (urlTG !== null) {
				var p = parseInt(urlTG, 10);
				if (p >= 0 && p <= 2) targetGame = p;
			}

			var gameSel = document.getElementById('mohaa-target-game');
			var loader = document.getElementById('mohaa-loader');
			var pickSection = document.getElementById('mohaa-pick-section');
			var playBtn = document.getElementById('mohaa-play-btn');
			var cacheStatus = document.getElementById('mohaa-cache-status');
			if (gameSel) gameSel.value = String(targetGame);

			function dbName(gd) { return 'mohaa-' + gd; }
			function openGameDB(gd) {
				return new Promise(function(ok) {
					try {
						var r = indexedDB.open(dbName(gd), DB_VER);
						r.onupgradeneeded = function(e) {
							var db = e.target.result;
							if (!db.objectStoreNames.contains(ST)) db.createObjectStore(ST);
						};
						r.onsuccess = function(e) { ok(e.target.result); };
						r.onerror = function() { ok(null); };
					} catch (e) {
						ok(null);
					}
				});
			}

			async function loadFromDB(gd) {
				var db = await openGameDB(gd);
				if (!db) return null;
				return new Promise(function(ok) {
					try {
						var tx = db.transaction(ST, 'readonly');
						var s = tx.objectStore(ST);
						var out = {};
						var n = 0;
						var cur = s.openCursor();
						cur.onsuccess = function(e) {
							var c = e.target.result;
							if (c) {
								out[c.key] = c.value;
								n++;
								c.continue();
							} else {
								db.close();
								ok(n ? out : null);
							}
						};
						cur.onerror = function() {
							db.close();
							ok(null);
						};
					} catch (e) {
						db.close();
						ok(null);
					}
				});
			}

			async function saveToDB(gd, files) {
				var db = await openGameDB(gd);
				if (!db) return;
				var keys = Object.keys(files);
				var bs = 20;
				for (var i = 0; i < keys.length; i += bs) {
					var chunk = keys.slice(i, i + bs);
					await new Promise(function(done) {
						try {
							var tx = db.transaction(ST, 'readwrite');
							var s = tx.objectStore(ST);
							chunk.forEach(function(k) { s.put(files[k], k); });
							tx.oncomplete = done;
							tx.onerror = function() { done(); };
						} catch (e) {
							done();
						}
					});
				}
				db.close();
			}

			async function hasCache(gd) {
				var db = await openGameDB(gd);
				if (!db) return false;
				return new Promise(function(ok) {
					try {
						var tx = db.transaction(ST, 'readonly');
						var req = tx.objectStore(ST).count();
						req.onsuccess = function() {
							db.close();
							ok(req.result > 0);
						};
						req.onerror = function() {
							db.close();
							ok(false);
						};
					} catch (e) {
						db.close();
						ok(false);
					}
				});
			}

			async function loadGameCaches(game) {
				var deps = GAME_DEPS[game] || ['main'];
				for (var i = 0; i < deps.length; i++) {
					if (!(await hasCache(deps[i]))) {
						console.log('MOHAAjs: Cache miss: ' + deps[i] + ' not cached');
						return null;
					}
				}
				var allFiles = {};
				for (var j = 0; j < deps.length; j++) {
					var files = await loadFromDB(deps[j]);
					if (files) {
						var ks = Object.keys(files);
						for (var k = 0; k < ks.length; k++) allFiles[ks[k]] = files[ks[k]];
						console.log('MOHAAjs: Loaded ' + ks.length + ' files from ' + deps[j] + ' cache');
					}
				}
				return Object.keys(allFiles).length ? allFiles : null;
			}

			async function cacheByGameDir(rawFiles) {
				var buckets = {};
				var keys = Object.keys(rawFiles);
				for (var i = 0; i < keys.length; i++) {
					var rel = keys[i].replace(/\\/g, '/');
					var slash = rel.indexOf('/');
					if (slash > 0) {
						var td = rel.substring(0, slash).toLowerCase();
						if (td === 'main' || td === 'mainta' || td === 'maintt') {
							if (!buckets[td]) buckets[td] = {};
							buckets[td][rel] = rawFiles[keys[i]];
							continue;
						}
					}
					if (!buckets.main) buckets.main = {};
					buckets.main[rel] = rawFiles[keys[i]];
				}
				var dirs = Object.keys(buckets);
				console.log('MOHAAjs: Caching files for: ' + dirs.join(', '));
				for (var d = 0; d < dirs.length; d++) {
					var n = Object.keys(buckets[dirs[d]]).length;
					await saveToDB(dirs[d], buckets[dirs[d]]);
					console.log('MOHAAjs: Cached ' + n + ' files to ' + dirs[d]);
				}
			}

			async function updateCacheStatus() {
				var parts = [];
				for (var k = 0; k < 3; k++) {
					var gd = GAME_DIRS[k];
					if (await hasCache(gd)) parts.push(GAME_NAMES[k] + ' [cached]');
				}
				if (cacheStatus) {
					cacheStatus.textContent = parts.length ? ('Cached: ' + parts.join(', ')) : 'No cached game files';
				}
			}

			async function mohaaReadDirHandle(h, prefix) {
				var files = {};
				for await (var entry of h.values()) {
					if (entry.name.startsWith('.')) continue;
					var p = prefix ? (prefix + '/' + entry.name) : entry.name;
					if (entry.kind === 'directory') {
						Object.assign(files, await mohaaReadDirHandle(entry, p));
					} else {
						try {
							var f = await entry.getFile();
							files[p] = new Uint8Array(await f.arrayBuffer());
						} catch (e) {
						}
					}
				}
				return files;
			}

			async function mohaaReadViaInput() {
				return new Promise(function(ok) {
					var inp = document.getElementById('mohaa-input-fb');
					inp.onchange = async function() {
						var list = Array.from(inp.files);
						var files = {};
						var area = document.getElementById('mohaa-prog-area');
						var bar = document.getElementById('mohaa-file-prog');
						var txt = document.getElementById('mohaa-prog-text');
						area.style.display = 'block';
						bar.max = list.length;
						bar.value = 0;
						for (var i = 0; i < list.length; i++) {
							var f = list[i];
							var rp = f.webkitRelativePath || f.name;
							var slash = rp.indexOf('/');
							if (slash >= 0) rp = rp.substring(slash + 1);
							if (!rp || rp.startsWith('.')) continue;
							try {
								files[rp] = new Uint8Array(await f.arrayBuffer());
							} catch (e) {
							}
							bar.value = i + 1;
							txt.textContent = 'Reading: ' + (i + 1) + '/' + list.length;
						}
						area.style.display = 'none';
						ok(Object.keys(files).length ? files : null);
					};
					inp.click();
				});
			}

			async function mohaaPickFiles() {
				var area = document.getElementById('mohaa-prog-area');
				var txt = document.getElementById('mohaa-prog-text');
				if (window.showDirectoryPicker) {
					try {
						area.style.display = 'block';
						txt.textContent = 'Reading files from folder...';
						var dh = await window.showDirectoryPicker({mode: 'read'});
						var files = await mohaaReadDirHandle(dh, '');
						area.style.display = 'none';
						if (Object.keys(files).length) return files;
					} catch (e) {
						area.style.display = 'none';
						if (e.name === 'AbortError') return null;
						console.warn('MOHAAjs: Directory picker error, trying fallback:', e);
					}
				}
				return mohaaReadViaInput();
			}

			function mohaaMapFilesToMemfs(rawFiles) {
				var mapped = {};
				var keys = Object.keys(rawFiles);
				var foundDirs = {};
				for (var i = 0; i < keys.length; i++) {
					var rel = keys[i].replace(/\\/g, '/');
					var firstSlash = rel.indexOf('/');
					if (firstSlash > 0) {
						var topDir = rel.substring(0, firstSlash).toLowerCase();
						if (topDir === 'main' || topDir === 'mainta' || topDir === 'maintt') foundDirs[topDir] = true;
					}
					mapped[rel] = rawFiles[keys[i]];
				}
				var dirList = Object.keys(foundDirs);
				if (dirList.length > 0) console.log('MOHAAjs: Detected game directories: ' + dirList.join(', '));
				else console.warn('MOHAAjs: No main/mainta/maintt subdirs found in selection');
				return mapped;
			}

			function startEngine() {
				var currentUrl = new URL(window.location.href);
				currentUrl.searchParams.set('com_target_game', String(targetGame));
				window.history.replaceState(null, '', currentUrl.toString());
				window.__mohaaTargetGame = targetGame;
				window.__mohaaGameDir = GAME_DIRS[targetGame] || 'main';
				setStatusMode('progress');
				var engineArgs = ['+set', 'com_target_game', String(targetGame)];
				var qMap = urlParams.get('map');
				if (qMap) engineArgs.push('+map', qMap);
				var qExec = urlParams.get('exec');
				if (qExec) engineArgs.push('+exec', qExec);
				if (urlParams.get('server') === '1' && !qExec) engineArgs.push('+exec', 'server.cfg');
				if (urlParams.get('dedicated') === '1') engineArgs.push('--dedicated');
				var qConnect = urlParams.get('connect');
				if (qConnect) engineArgs.push('+connect', qConnect);
				var qRelay = urlParams.get('relay');
				if (qRelay) {
					qRelay = qRelay.replace('ws://', '').replace('wss://', '');
					engineArgs.push('+set', 'net_ws_relay', qRelay);
				}
				engine.startGame({
					'args': engineArgs,
					'onProgress': function(current, total) {
						if (current > 0 && total > 0) {
							statusProgress.value = current;
							statusProgress.max = total;
						} else {
							statusProgress.removeAttribute('value');
							statusProgress.removeAttribute('max');
						}
					}
				}).then(function() {
					setStatusMode('hidden');
				}, displayFailureNotice);
			}

			statusOverlay.style.visibility = 'hidden';
			loader.style.display = 'flex';
			if (pickSection) pickSection.style.display = 'none';
			await updateCacheStatus();

			await new Promise(function(resolve) {
				playBtn.onclick = async function() {
					targetGame = parseInt(gameSel.value, 10) || 0;
					window.__mohaaTargetGame = targetGame;
					playBtn.disabled = true;
					playBtn.textContent = 'Loading...';
					var cached = await loadGameCaches(targetGame);
					if (cached) {
						console.log('MOHAAjs: Cache hit for ' + GAME_NAMES[targetGame]);
						window.__mohaaLocalFiles = cached;
						loader.style.display = 'none';
						resolve();
						return;
					}
					playBtn.style.display = 'none';
					if (pickSection) pickSection.style.display = 'block';
					document.getElementById('mohaa-pick-btn').onclick = async function() {
						this.disabled = true;
						var rawFiles = await mohaaPickFiles();
						if (rawFiles) {
							targetGame = parseInt(gameSel.value, 10) || 0;
							window.__mohaaTargetGame = targetGame;
							window.__mohaaGameDir = GAME_DIRS[targetGame] || 'main';
							var files = mohaaMapFilesToMemfs(rawFiles);
							var n = Object.keys(files).length;
							console.log('MOHAAjs: Read ' + n + ' local files (target: ' + GAME_NAMES[targetGame] + ')');
							window.__mohaaLocalFiles = files;
							loader.style.display = 'none';
							cacheByGameDir(files).catch(function(e) {
								console.warn('MOHAAjs: Cache save failed', e);
							});
							resolve();
						} else {
							this.disabled = false;
						}
					};
				};
				document.getElementById('mohaa-skip-btn').onclick = function() {
					targetGame = parseInt(gameSel.value, 10) || 0;
					window.__mohaaTargetGame = targetGame;
					loader.style.display = 'none';
					resolve();
				};
			});

			startEngine();
		})().catch(displayFailureNotice);
/* MOHAA_BOOT_END */

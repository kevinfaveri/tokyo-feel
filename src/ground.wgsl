// ---- the still scenery: the road and the track, the crossing's posts, the
// trees, the houses. Drawn once, and kept as (light, material + how far up
// its normal points, depth, warm light). ----------------------------------------

var<private> g_obj: i32;
var<private> g_q: vec3<f32>;

fn tk_ground(p: vec3<f32>) -> f32 {
	var mat = 3;
	var obj = -1;
	var q_hit = vec3<f32>(0.0);
	let fy = p.y - K_FLOOR;
	var d = p.y - tk_floor_y(p.z);
	if (d < g_near + 0.1) {
		d = d - 0.008 * tk_noise(p * 9.0);
	}

	// The rails.
	{
		let ry = abs(p.y - (K_FLOOR + K_BED_H + 0.03)) - 0.03;
		let rz = abs(abs(p.z - K_TRACK_Z) - K_RAIL) - 0.022;
		let dr = length(max(vec2<f32>(ry, rz), vec2<f32>(0.0))) + min(max(ry, rz), 0.0);
		if (dr < d) {
			d = dr;
			mat = 11;
		}
	}

	// A fence along each side of the track, clear of the road.
	{
		let ax = abs(p.x) - (K_WALK + 0.05);
		let qx = (fract(p.x / 0.4) - 0.5) * 0.4;
		for (var s = 0; s < 2; s = s + 1) {
			let dz = p.z - (K_TRACK_Z + (f32(s) * 2.0 - 1.0) * (K_BED + 0.28));
			var df = max(length(vec2<f32>(qx, dz)) - 0.02, fy - 0.34);
			df = min(df, length(vec2<f32>(fy - 0.3, dz)) - 0.014);
			df = min(df, length(vec2<f32>(fy - 0.16, dz)) - 0.014);
			df = max(df, -ax);
			if (df < d) {
				d = df;
				mat = 7;
			}
		}
	}

	// The crossing's posts: a striped pole, a crossbuck, two lamps.
	for (var i = 0; i < N_XING; i = i + 1) {
		let c = K_XING[i];
		let q = vec3<f32>(p.x - c.x, fy, (p.z - c.y) * c.z);
		let bd = length(q - vec3<f32>(0.0, 0.7, 0.0)) - 0.95;
		if (bd > g_near) {
			d = min(d, bd);
			continue;
		}
		var dp = tk_cap(q, vec3<f32>(0.0), vec3<f32>(0.0, 1.3, 0.0), 0.028, 0.024);
		if (dp < d) {
			d = dp;
			mat = 12;
			if (fract(q.y * 4.0) < 0.5) {
				mat = 13;
			}
		}
		dp = tk_box(q - vec3<f32>(0.0, 0.22, 0.0), vec3<f32>(0.07, 0.22, 0.06));
		if (dp < d) {
			d = dp;
			mat = 12;
		}
		let u = vec2<f32>(q.x, q.y - 1.16);
		let a = (u.x + u.y) * 0.70710678;
		let b = (u.x - u.y) * 0.70710678;
		let d1 = tk_box(vec3<f32>(a, b, q.z - 0.03), vec3<f32>(0.25, 0.034, 0.012));
		let d2 = tk_box(vec3<f32>(b, a, q.z - 0.03), vec3<f32>(0.25, 0.034, 0.012));
		if (min(d1, d2) < d) {
			d = min(d1, d2);
			mat = 12;
			if (fract(abs(select(b, a, d1 < d2)) * 7.0 + 0.25) < 0.5) {
				mat = 13;
			}
		}
		let lx = abs(q.x) - 0.115;
		dp = tk_box(vec3<f32>(lx, q.y - 0.92, q.z - 0.025), vec3<f32>(0.08, 0.08, 0.03));
		if (dp < d) {
			d = dp;
			mat = 13;
		}
		dp = (length(vec3<f32>(lx, q.y - 0.92, (q.z - 0.05) * 2.0)) - 0.052) * 0.5;
		if (dp < d) {
			d = dp;
			mat = 14;
			if (q.x > 0.0) {
				mat = 15;
			}
		}
	}

	// Utility poles, their arms across the wires' way, a transformer each.
	for (var i = 0; i < N_POLE; i = i + 1) {
		let c = K_POLE[i];
		let q = vec3<f32>(p.x - c.x, fy, p.z - c.y);
		var dp = tk_cap(q, vec3<f32>(0.0), vec3<f32>(0.0, c.z, 0.0), 0.042, 0.032);
		dp = min(dp, tk_cap(q, vec3<f32>(0.0, c.z - 0.1, -c.w), vec3<f32>(0.0, c.z - 0.1, c.w), 0.016, 0.016));
		dp = min(dp, tk_cap(q, vec3<f32>(0.0, c.z - 0.34, -c.w * 0.7), vec3<f32>(0.0, c.z - 0.34, c.w * 0.7), 0.016, 0.016));
		if (dp < d) {
			d = dp;
			mat = 7;
		}
		dp = tk_cap(q, vec3<f32>(0.1, c.z - 0.78, 0.0), vec3<f32>(0.1, c.z - 0.58, 0.0), 0.06, 0.06);
		if (dp < d) {
			d = dp;
			mat = 11;
		}
	}
	for (var i = 0; i < N_WIRE; i = i + 1) {
		let dp = tk_cap(p, K_WIRE_A[i], K_WIRE_B[i], 0.008, 0.008);
		if (dp < d) {
			d = dp;
			mat = 13;
		}
	}

	// Street lamps.
	for (var i = 0; i < N_LAMP; i = i + 1) {
		let c = K_LAMP[i];
		let q = vec3<f32>(p.x - c.x, fy, p.z - c.y);
		var dp = tk_cap(q, vec3<f32>(0.0), vec3<f32>(0.0, c.z, 0.0), 0.03, 0.022);
		dp = min(dp, tk_cap(q, vec3<f32>(0.0, c.z, 0.0), vec3<f32>(c.w, c.z + 0.06, 0.0), 0.02, 0.018));
		if (dp < d) {
			d = dp;
			mat = 11;
		}
		dp = tk_ell(q, vec3<f32>(c.w, c.z + 0.03, 0.0), vec3<f32>(0.1, 0.035, 0.06));
		if (dp < d) {
			d = dp;
			mat = 16;
		}
	}

	// A vending machine by the road.
	{
		let q = vec3<f32>(p.x - K_VEND.x, fy - 0.38, p.z - K_VEND.y);
		let dp = tk_box(q, vec3<f32>(0.2, 0.38, 0.13)) - 0.01;
		if (dp < d) {
			d = dp;
			mat = 17;
			obj = -1;
			q_hit = q;
		}
	}

	// Trees: a trunk, three boughs, and a canopy of soft blobs.
	for (var i = 0; i < N_TREE; i = i + 1) {
		let tt = K_TREE_T[i];
		let top = K_TREE_L[i].xyz;
		var dw = tk_cap(p, vec3<f32>(tt.x, tk_floor_y(tt.y) - 0.05, tt.y), top, 0.085, 0.05);
		for (var j = 0; j < 3; j = j + 1) {
			dw = tk_smin(dw, tk_cap(p, top, K_TREE_BR[i * 3 + j].xyz, 0.045, 0.02), 0.04);
		}
		if (dw < g_near + 0.05) {
			dw = dw - 0.012 * tk_noise(p * vec3<f32>(16.0, 5.0, 16.0));
		}
		if (dw < d) {
			d = dw;
			mat = 4;
			obj = -1;
		}
		let tb = K_TREE_B[i];
		let bd = length(p - tb.xyz) - tb.w;
		if (bd > g_near) {
			d = min(d, bd);
			continue;
		}
		var dc = 1e9;
		for (var j = 0; j < 6; j = j + 1) {
			let b = K_BLOB[i * 6 + j];
			dc = tk_smin(dc, tk_ell(p, b.xyz, vec3<f32>(b.w, b.w * 0.78, b.w)), 0.12);
		}
		dc = (dc - 0.1 * tk_noise(p * 4.5) - 0.04 * tk_noise(p * 13.0)) * 0.75;
		if (dc < d) {
			d = dc;
			mat = 5;
			obj = -1;
			if (tt.w > 0.5) {
				mat = 6;
			}
		}
	}

	// Bushes.
	for (var i = 0; i < N_BUSH; i = i + 1) {
		let b = K_BUSH[i];
		let bd = length(p - b.xyz) - b.w - 0.1;
		if (bd > g_near) {
			d = min(d, bd);
			continue;
		}
		let db = (tk_ell(p, b.xyz, vec3<f32>(b.w, b.w * 0.7, b.w * 0.9)) - 0.05 * tk_noise(p * 9.0)) * 0.8;
		if (db < d) {
			d = db;
			mat = 6;
			obj = 100 + i;
		}
	}

	// Houses: walls, and a gable roof where the roof has a height.
	for (var i = 0; i < N_HOUSE; i = i + 1) {
		let c = K_HOUSE_C[i];
		let h = K_HOUSE_H[i];
		let q = vec3<f32>(p.x - c.x, fy, p.z - c.y);
		var dh = tk_box(q - vec3<f32>(0.0, h.x * 0.5, 0.0), vec3<f32>(c.z, h.x * 0.5, c.w));
		var hm = i32(h.z);
		if (h.y > 0.0) {
			let s = h.y / (c.w + 0.1);
			var dr = ((q.y - h.x) + abs(q.z) * s - h.y) / sqrt(1.0 + s * s);
			dr = max(dr, abs(q.x) - (c.z + 0.07));
			dr = max(dr, h.x - 0.02 - q.y);
			if (dr < dh) {
				dh = dr;
				hm = 9;
			}
		}
		if (dh < d) {
			d = dh;
			mat = hm;
			obj = i;
			q_hit = q;
		}
	}

	g_mat = mat;
	g_obj = obj;
	g_q = q_hit;
	return d;
}

// Each surface's grain.
fn tk_grain(m: i32, p: vec3<f32>) -> f32 {
	var a = 0.5;
	switch m {
		case 0: { a = 0.5 + 0.22 * (tk_noise(p * 22.0) - 0.5); }
		case 1: { a = 0.3 + 0.75 * tk_cells(p * 20.0, 4.0); }
		case 3: { a = 0.5 + 0.4 * (tk_noise(p * vec3<f32>(30.0, 8.0, 30.0)) - 0.5); }
		case 4: { a = 0.5 + 0.28 * sin(p.y * 32.0 + 4.0 * tk_noise(p * 6.0)); }
		case 5: { a = 0.92 - 1.1 * tk_cells(p * 8.0, 2.0) + 0.25 * (tk_noise(p * 19.0) - 0.5); }
		case 6: { a = 0.85 - 1.0 * tk_cells(p * 10.0, 6.0) + 0.25 * (tk_noise(p * 17.0) - 0.5); }
		case 7: { a = 0.5 + 0.14 * (tk_noise(p * 12.0) - 0.5); }
		case 8, 20: { a = 0.5 + 0.07 * sin(p.y * 62.0); }
		case 9: { a = 0.5 + 0.2 * sin(p.x * 44.0) * sin(p.y * 52.0 + p.z * 30.0); }
		default: {}
	}
	return clamp(a, 0.0, 1.0);
}

fn run(input: PassInput) -> vec4<f32> {
	let cell = floor(input.pixel);
	g_thr = tk_bayer(cell + 2.0) * 0.96 + 0.02;
	tk_camera(cell, input.size, input.params[1]);
	let none = vec4<f32>(0.0, 0.0, 1e4, 0.0);

	g_near = 0.05;
	var t = 0.5;
	var hit = false;
	for (var i = 0; i < 170; i = i + 1) {
		let dist = tk_ground(g_ro + g_rd * t);
		if (dist < 0.003 + t * 0.0005) {
			hit = true;
			break;
		}
		t = t + dist * 0.8;
		if (t > 30.0) {
			break;
		}
	}
	if (!hit) {
		return none;
	}
	let p = g_ro + g_rd * t;
	g_near = 4.0;
	let d0 = tk_ground(p);
	var m = g_mat;
	let obj = g_obj;
	let q = g_q;
	// Far off, the land thins out into the sky, in dots.
	if (1.0 - smoothstep(16.0, 26.0, t) <= g_thr) {
		return none;
	}
	let k = vec2<f32>(1.0, -1.0) * 0.008;
	let n = normalize(k.xyy * tk_ground(p + k.xyy) + k.yyx * tk_ground(p + k.yyx) + k.yxy * tk_ground(p + k.yxy) + k.xxx * tk_ground(p + k.xxx));
	let h = 0.03;
	var occ = max(0.0, 1.0 - tk_ground(p + n * 2.0 * h) / (2.0 * h));
	occ = occ + max(0.0, 1.0 - tk_ground(p + n * 5.0 * h) / (5.0 * h));
	occ = occ + max(0.0, 1.0 - tk_ground(p + n * 10.0 * h) / (10.0 * h));
	let ao = max(0.0, 1.0 - occ / 2.2);

	// What the ground is, by where on it: the track's bed and sleepers, the
	// road and its paint, the pavements, the lanes along the track.
	let ax = abs(p.x);
	let tz = abs(p.z - K_TRACK_Z);
	if (m == 3) {
		let lane = (p.z > 1.85 && p.z < 2.6) || (p.z < -2.4 && p.z > -3.0);
		if (tz < K_BED + 0.12) {
			m = 1;
			if (ax < K_ROAD) {
				m = 0;
			} else if (tz < K_RAIL + 0.17 && fract(p.x / 0.3) < 0.42) {
				m = 7;
			}
		} else if (ax < K_ROAD) {
			m = 0;
			let stop = (p.z > 1.1 && p.z < 1.2) || (p.z < -2.1 && p.z > -2.2);
			if (stop && ax < K_ROAD - 0.14) {
				m = 2;
			}
			if (abs(ax - (K_ROAD - 0.07)) < 0.022 && !lane) {
				m = 2;
			}
			if (ax < 0.022 && fract(p.z * 1.4) < 0.5 && (p.z > 1.35 || p.z < -2.35)) {
				m = 2;
			}
		} else if (lane) {
			m = 0;
		} else if (ax < K_WALK) {
			m = 7;
		}
	}
	// Fallen petals, on whatever lies flat.
	var petal = false;
	if ((m == 0 || m == 1 || m == 3 || m == 7) && n.y > 0.7) {
		var share = 0.032;
		if (m == 3) {
			share = 0.11;
		}
		petal = tk_h31(floor(vec3<f32>(p.x * 27.0, 3.0, p.z * 27.0))) < share;
	}
	// Windows, on a wall facing the viewer: some lit.
	if ((m == 8 || m == 20) && n.z > 0.6 && obj >= 0 && obj < N_HOUSE) {
		let hc = K_HOUSE_C[obj];
		let hh = K_HOUSE_H[obj];
		let gx = q.x / 0.36 + 0.5 * f32(obj);
		let gy = (q.y - 0.14) / 0.46;
		let fx = fract(gx);
		let fy = fract(gy);
		if (q.y > 0.14 && q.y < hh.x - 0.06 && abs(q.x) < hc.z - 0.06 && fx > 0.22 && fx < 0.78 && fy > 0.3 && fy < 0.82) {
			m = 21;
			if (tk_h31(vec3<f32>(floor(gx), floor(gy), f32(obj) + 3.0)) > 0.42) {
				m = 10;
			}
		}
	}
	// The vending machine's lit front, and what it sells.
	if (m == 17 && n.z > 0.6 && abs(q.x) < 0.16 && q.y > -0.2 && q.y < 0.3) {
		m = 18;
		if (fract(q.y * 7.0) < 0.55) {
			let pick = tk_h31(vec3<f32>(floor(q.x * 22.0), floor(q.y * 7.0), 1.0));
			if (pick < 0.3) {
				m = 23;
			} else if (pick < 0.55) {
				m = 24;
			}
		}
	}
	// Every other bush is in flower.
	var bloom = false;
	if (m == 6 && obj >= 100 && ((obj - 100) & 1) == 1) {
		bloom = tk_cells(p * 16.0, 9.0) < 0.3;
	}

	let grain = tk_grain(m, p);
	// The evening's light: soft, from the front and above.
	let ndl = dot(n, normalize(vec3<f32>(-0.35, 0.65, 0.65)));
	var l = 0.2 + 0.8 * clamp(ndl * 0.7 + 0.3, 0.0, 1.0);
	l = l * mix(0.4, 1.0, ao);
	l = l + (grain - 0.5) * 0.4;
	if (petal || bloom) {
		m = 5;
		l = 0.78 + 0.2 * grain;
	}
	// Warm light pooling under the lamps and by the vending machine.
	var lw = 0.0;
	if (m != 10 && m != 16 && m != 18 && m != 23 && m != 24) {
		for (var i = 0; i < N_LIGHT; i = i + 1) {
			let lv = K_LIGHT[i].xyz - p;
			let ld = max(length(lv), 1e-4);
			lw = lw + K_LIGHT[i].w * (max(dot(n, lv / ld), 0.0) * 0.85 + 0.1) / (1.0 + ld * ld * 5.0);
		}
	}
	return vec4<f32>(clamp(l, 0.0, 1.0), f32(m) + clamp(n.y * 0.45 + 0.5, 0.02, 0.98), t, lw);
}

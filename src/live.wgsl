// ---- what moves: the train, the gates, the people and a dog; then the lamps'
// glow, the petals, the sky and the palette. Drawn every frame, over the still
// scenery's kept pixels. --------------------------------------------------------

// The train: when its nose comes into the frame, how fast, and its size.
const K_ARRIVE: f32 = 4.6;
const K_ENTER: f32 = 6.5;
const K_SPEED: f32 = 7.0;
const K_CAR: f32 = 7.0;
const K_TRAIN_L: f32 = 35.0;
const K_TRAIN_H: f32 = 1.5;
const K_TRAIN_W: f32 = 0.52;

var<private> g_best: f32;
var<private> g_id: i32;
var<private> g_n: vec3<f32>;
var<private> g_ao: f32;
var<private> g_m: i32;
var<private> g_det: f32;
var<private> g_part: i32;
var<private> g_lp: vec3<f32>;
var<private> g_who: vec4<f32>;
var<private> g_walk: f32;
var<private> g_rs: i32;
var<private> g_rc: i32;

// A person, feet at the origin, facing +x: (kind, size, coat, stride) in g_who.
fn tk_person(p0: vec3<f32>) -> f32 {
	let p = p0 / g_who.y;
	let kind = i32(g_who.x);
	let sw = sin(g_who.w) * g_walk;
	var part = 0;
	var d = tk_cap(p, vec3<f32>(0.0, 0.33, 0.045), vec3<f32>(sw * 0.16, 0.03 + max(-sw, 0.0) * 0.04, 0.045), 0.04, 0.032);
	d = min(d, tk_cap(p, vec3<f32>(0.0, 0.33, -0.045), vec3<f32>(-sw * 0.16, 0.03 + max(sw, 0.0) * 0.04, -0.045), 0.04, 0.032));
	var dt = tk_ell(p, vec3<f32>(0.0, 0.45, 0.0), vec3<f32>(0.08, 0.15, 0.105));
	if (kind == 0) {
		// A long coat.
		dt = tk_smin(dt, tk_ell(p, vec3<f32>(0.0, 0.32, 0.0), vec3<f32>(0.085, 0.11, 0.1)), 0.03);
	}
	dt = min(dt, tk_cap(p, vec3<f32>(0.0, 0.53, 0.115), vec3<f32>(-sw * 0.1, 0.35, 0.13), 0.028, 0.023));
	dt = min(dt, tk_cap(p, vec3<f32>(0.0, 0.53, -0.115), vec3<f32>(sw * 0.1, 0.35, -0.13), 0.028, 0.023));
	if (dt < d) {
		d = dt;
		part = 1;
	}
	let dh = length(p - vec3<f32>(0.005, 0.625, 0.0)) - 0.06;
	if (dh < d) {
		d = dh;
		part = 2;
	}
	if (kind == 1 || kind == 2) {
		// A bag on the back.
		let db = tk_box(p - vec3<f32>(-0.1, 0.46, 0.0), vec3<f32>(0.03, 0.075, 0.065)) - 0.012;
		if (db < d) {
			d = db;
			part = 3;
		}
	}
	if (kind == 2) {
		// A child's hat.
		let dc = tk_ell(p, vec3<f32>(0.0, 0.665, 0.0), vec3<f32>(0.088, 0.035, 0.088));
		if (dc < d) {
			d = dc;
			part = 4;
		}
	}
	g_part = part;
	g_lp = p;
	return d * g_who.y;
}

fn tk_dog(p: vec3<f32>) -> f32 {
	let sw = sin(g_who.w * 1.6) * g_walk;
	let q = vec3<f32>(p.x, p.y, abs(p.z));
	var d = tk_ell(p, vec3<f32>(0.0, 0.15, 0.0), vec3<f32>(0.13, 0.065, 0.06));
	d = tk_smin(d, length(p - vec3<f32>(0.14, 0.22, 0.0)) - 0.055, 0.03);
	d = min(d, tk_ell(p, vec3<f32>(0.2, 0.2, 0.0), vec3<f32>(0.04, 0.025, 0.028)));
	d = min(d, tk_cap(q, vec3<f32>(0.13, 0.26, 0.03), vec3<f32>(0.125, 0.3, 0.04), 0.018, 0.008));
	d = min(d, tk_cap(q, vec3<f32>(0.08, 0.12, 0.035), vec3<f32>(0.08 + sw * 0.06, 0.012, 0.035), 0.02, 0.016));
	d = min(d, tk_cap(q, vec3<f32>(-0.09, 0.12, 0.035), vec3<f32>(-0.09 - sw * 0.06, 0.012, 0.035), 0.02, 0.016));
	d = min(d, tk_cap(p, vec3<f32>(-0.12, 0.19, 0.0), vec3<f32>(-0.13, 0.27, 0.0), 0.025, 0.02));
	g_part = 5;
	g_lp = p;
	return d;
}

fn tk_figure(id: i32, p: vec3<f32>) -> f32 {
	if (id == 3) {
		return tk_dog(p);
	}
	return tk_person(p);
}

// One figure along the ray, inside its box: the nearest hit so far is kept,
// with its material, normal and occlusion.
fn tk_try(id: i32, o: vec3<f32>, d: vec3<f32>, R: mat3x3<f32>, lo: vec3<f32>, hi: vec3<f32>) {
	let ds = select(d, vec3<f32>(1e-6), abs(d) < vec3<f32>(1e-6));
	let ta = (lo - o) / ds;
	let tb = (hi - o) / ds;
	let tn = min(ta, tb);
	let tx = max(ta, tb);
	let t0 = max(max(tn.x, tn.y), max(tn.z, 0.0));
	let t1 = min(min(tx.x, tx.y), min(tx.z, g_best));
	if (t0 >= t1) {
		return;
	}
	var t = t0;
	for (var i = 0; i < 40; i = i + 1) {
		let p = o + d * t;
		let dist = tk_figure(id, p);
		if (dist < 0.004) {
			let part = g_part;
			let lp = g_lp;
			let kind = i32(g_who.x);
			var m = 42;
			var det = 0.5;
			if (part == 5) {
				m = 43;
				det = 0.5 + 1.2 * (lp.y - 0.15);
				if (lp.y < 0.11 || lp.x > 0.19) {
					m = 49;
				}
			} else if (part == 1) {
				m = i32(g_who.z);
				det = 0.5 + 0.5 * (lp.y - 0.45);
			} else if (part == 2) {
				m = 37;
				if (lp.x > 0.022 && lp.y < 0.655) {
					m = 36;
				}
			} else if (part == 3) {
				m = 41;
				if (kind == 2) {
					m = 45;
				}
			} else if (part == 4) {
				m = 44;
			} else if (lp.y < 0.05) {
				m = 37;
			}
			g_best = t;
			g_id = id;
			g_m = m;
			g_det = clamp(det, 0.0, 1.0);
			let k = 0.007;
			let nl = normalize(vec3<f32>(
				tk_figure(id, p + vec3<f32>(k, 0.0, 0.0)),
				tk_figure(id, p + vec3<f32>(0.0, k, 0.0)),
				tk_figure(id, p + vec3<f32>(0.0, 0.0, k))
			) - dist);
			let h = 0.02;
			var occ = max(0.0, 1.0 - tk_figure(id, p + nl * 3.0 * h) / (3.0 * h));
			occ = occ + max(0.0, 1.0 - tk_figure(id, p + nl * 8.0 * h) / (8.0 * h));
			g_ao = max(0.0, 1.0 - occ / 1.6);
			g_n = R * nl;
			return;
		}
		t = t + dist * 0.8;
		if (t > t1) {
			return;
		}
	}
}

// Where a ray meets a round bar from `a` to `b`, or -1.
fn tk_ray_bar(ro: vec3<f32>, rd: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
	let ba = b - a;
	let oa = ro - a;
	let baba = dot(ba, ba);
	let bard = dot(ba, rd);
	let baoa = dot(ba, oa);
	let rdoa = dot(rd, oa);
	let qa = baba - bard * bard;
	var qb = baba * rdoa - baoa * bard;
	var qc = baba * dot(oa, oa) - baoa * baoa - r * r * baba;
	var h = qb * qb - qa * qc;
	if (h < 0.0) {
		return -1.0;
	}
	let t = (-qb - sqrt(h)) / qa;
	let y = baoa + t * bard;
	if (y > 0.0 && y < baba) {
		return t;
	}
	var oc = oa;
	if (y > 0.0) {
		oc = ro - b;
	}
	qb = dot(rd, oc);
	qc = dot(oc, oc) - r * r;
	h = qb * qb - qc;
	if (h > 0.0) {
		return -qb - sqrt(h);
	}
	return -1.0;
}

// Walker `i` at `ph` in the round: (x, z, heading, how much it's walking);
// x is 1000 while it's off stage.
fn tk_path(i: i32, ph: f32) -> vec4<f32> {
	for (var k = 0; k < N_KEY - 1; k = k + 1) {
		let a = K_PATH[i * N_KEY + k];
		let b = K_PATH[i * N_KEY + k + 1];
		if (ph >= a.x && ph < b.x) {
			let span = b.x - a.x;
			if (span < 0.2) {
				break;
			}
			let v = b.yz - a.yz;
			let at = mix(a.yz, b.yz, (ph - a.x) / span);
			if (length(v) < 0.02) {
				return vec4<f32>(at.x, at.y, a.w, 0.0);
			}
			let pace = smoothstep(0.0, 0.5, ph - a.x) * smoothstep(0.0, 0.5, b.x - ph);
			return vec4<f32>(at.x, at.y, atan2(v.y, v.x), 0.35 + 0.65 * pace);
		}
	}
	return vec4<f32>(1000.0, 0.0, 0.0, 0.0);
}

fn tk_yaw(a: f32) -> mat3x3<f32> {
	let c = cos(a);
	let s = sin(a);
	return mat3x3<f32>(vec3<f32>(c, 0.0, s), vec3<f32>(0.0, 1.0, 0.0), vec3<f32>(-s, 0.0, c));
}

// ---- colour ----------------------------------------------------------------

fn tk_ramp(start: i32, count: i32, l0: f32) -> vec3<f32> {
	g_rs = start;
	g_rc = count;
	let l = clamp(l0, 0.0, 1.0) * f32(count - 1);
	let i = i32(floor(l));
	return mix(K_PAL[start + i], K_PAL[start + min(i + 1, count - 1)], fract(l));
}

// A material lit by `l`, through its ramp of the palette. `lamps` says which
// of the crossing's two lamps is lit; `blue` picks the train's livery.
fn tk_colour(m: i32, l: f32, lamps: vec2<f32>, blue: bool) -> vec3<f32> {
	switch m {
		case 0: { return tk_ramp(P_GREY, 6, l * 0.42 + 0.06); }
		case 1: { return tk_ramp(P_GREY, 6, l * 0.55 + 0.16); }
		case 2: { return tk_ramp(P_GREY, 6, l * 0.3 + 0.7); }
		case 3: { return tk_ramp(P_GREEN, 5, l * 0.8); }
		case 4: { return tk_ramp(P_WOOD, 5, l * 0.7); }
		case 5: { return tk_ramp(P_PINK, 6, l * 0.85 + 0.15); }
		case 6: { return tk_ramp(P_GREEN, 5, l * 0.9 + 0.05); }
		case 7: { return tk_ramp(P_GREY, 6, l * 0.55 + 0.28); }
		case 8: { return tk_ramp(P_WOOD, 5, l * 0.45 + 0.55); }
		case 9: { return tk_ramp(P_BLUE, 4, l * 0.6); }
		case 10: { return tk_ramp(P_WARM, 5, 0.74); }
		case 11: { return tk_ramp(P_GREY, 6, l * 0.75 + 0.12); }
		case 12, 34: { return tk_ramp(P_WARM, 5, l * 0.4 + 0.45); }
		case 13, 35: { return tk_ramp(P_GREY, 6, l * 0.14); }
		case 14: { return tk_ramp(P_RED, 4, 0.18 + 0.8 * lamps.x); }
		case 15: { return tk_ramp(P_RED, 4, 0.18 + 0.8 * lamps.y); }
		case 16, 46: { return tk_ramp(P_WARM, 5, 0.97); }
		case 17: { return tk_ramp(P_BLUE, 4, l * 0.7 + 0.2); }
		case 18: { return tk_ramp(P_WARM, 5, 0.86); }
		case 20: { return tk_ramp(P_GREY, 6, l * 0.5 + 0.22); }
		case 21: { return tk_ramp(P_BLUE, 4, l * 0.3 + 0.08); }
		case 23, 48: { return tk_ramp(P_RED, 4, 0.82); }
		case 24: { return tk_ramp(P_BLUE, 4, 0.9); }
		case 30: { return tk_ramp(P_GREY, 6, l * 0.42 + 0.52); }
		case 31: {
			if (blue) {
				return tk_ramp(P_BLUE, 4, l * 0.4 + 0.55);
			}
			return tk_ramp(P_GREEN, 5, l * 0.45 + 0.5);
		}
		case 32: { return tk_ramp(P_WARM, 5, 0.9); }
		case 33: { return tk_ramp(P_GREY, 6, l * 0.2 + 0.03); }
		case 36: { return tk_ramp(P_WOOD, 5, l * 0.4 + 0.6); }
		case 37: { return tk_ramp(P_GREY, 6, l * 0.16 + 0.02); }
		case 38: { return tk_ramp(P_BLUE, 4, l * 0.7); }
		case 39, 45: { return tk_ramp(P_RED, 4, l * 0.6 + 0.2); }
		case 40: { return tk_ramp(P_WOOD, 5, l * 0.5 + 0.45); }
		case 41: { return tk_ramp(P_GREY, 6, l * 0.3 + 0.08); }
		case 42: { return tk_ramp(P_GREY, 6, l * 0.26 + 0.05); }
		case 43: { return tk_ramp(P_WOOD, 5, l * 0.55 + 0.38); }
		case 44: { return tk_ramp(P_WARM, 5, l * 0.3 + 0.62); }
		case 49: { return tk_ramp(P_GREY, 6, l * 0.3 + 0.7); }
		default: { return tk_ramp(P_GREY, 6, l); }
	}
}

// The nearest palette colour, among the sky's ramp and the ramp at
// [rs, rs + rc): a surface keeps to its own family of colours however the
// evening air between tints it (a pink tree never turns green).
fn tk_nearest(col: vec3<f32>, cell: vec2<f32>, dither: f32, rs: i32, rc: i32, warm: bool) -> vec3<f32> {
	var c1 = col;
	var c2 = col;
	var d1 = 1e9;
	var d2 = 1e9;
	for (var i = 0; i < N_PAL; i = i + 1) {
		let own = i < 10 || (i >= rs && i < rs + rc);
		let lit = warm && i >= P_WARM && i < P_RED;
		if (!own && !lit) {
			continue;
		}
		let pc = K_PAL[i];
		let e = col - pc;
		let w = e * vec3<f32>(0.30, 0.59, 0.11);
		let dd = dot(w, w) + 0.25 * dot(e, e);
		if (dd < d1) {
			d2 = d1;
			c2 = c1;
			d1 = dd;
			c1 = pc;
		} else if (dd < d2) {
			d2 = dd;
			c2 = pc;
		}
	}
	let axis = c2 - c1;
	let t = clamp(dot(col - c1, axis) / max(dot(axis, axis), 1e-5), 0.0, 0.5);
	if (tk_bayer(cell) < t * dither) {
		return c2;
	}
	return c1;
}

// The evening sky along a ray: the glow at the horizon rising into the dark,
// thin cloud, stars and a moon, and a far city with its tower, lit.
fn tk_sky(rd: vec3<f32>, cell: vec2<f32>, res: vec2<f32>, e: f32) -> vec3<f32> {
	let up = rd.y;
	let az = rd.x / max(-rd.z, 0.2);
	// The tower.
	let ty = up / 0.17;
	if (ty > 0.0 && ty < 1.0 && abs(az + 0.116) < 0.0032 + 0.028 * pow(1.0 - ty, 2.4)) {
		if (ty > 0.8 || fract(ty * 5.0) > 0.55) {
			return K_PAL[P_WARM + 4];
		}
		return K_PAL[P_WARM + 2];
	}
	// The far city: blocks along the horizon, a window lit here and there.
	let block = floor(az * 30.0);
	var roof = 0.01 + 0.03 * tk_h31(vec3<f32>(block, 1.0, 5.0));
	if (tk_h31(vec3<f32>(block, 2.0, 9.0)) > 0.86) {
		roof = roof + 0.045;
	}
	if (up < roof) {
		let wx = floor(fract(az * 30.0) * 4.0);
		if (up > 0.0 && wx > 0.5 && tk_h31(vec3<f32>(block * 4.0 + wx, floor(up * 300.0), 4.0)) > 0.8) {
			return K_PAL[P_WARM + 3];
		}
		return K_PAL[2];
	}
	// The moon, a crescent, and stars higher up.
	let mc = vec2<f32>(floor(res.x * 0.79), floor(res.y * 0.17));
	let mr = max(3.5, res.y * 0.028);
	if (length(cell - mc) < mr && length(cell - mc - vec2<f32>(mr * 0.45, -mr * 0.3)) > mr * 0.95) {
		return K_PAL[9];
	}
	if (up > 0.16) {
		let star = tk_h31(vec3<f32>(cell.x, cell.y, 7.0));
		if (star > 0.9935 && sin(e * (0.6 + star * 40.0) + star * 90.0) > -0.6) {
			return K_PAL[8];
		}
	}
	var li = clamp(0.92 - 2.7 * up, 0.06, 0.95);
	let cloud = tk_noise(vec3<f32>(az * 2.4 / (up + 0.35) + e * 0.006, up * 17.0, 3.0));
	if (up > 0.03 && cloud > 0.58) {
		li = min(li + 0.07 + 0.4 * (cloud - 0.58), 0.98);
	}
	let wi = li * 9.0;
	var idx = i32(floor(wi));
	if (fract(wi) > tk_bayer(cell)) {
		idx = idx + 1;
	}
	return K_PAL[min(idx, 9)];
}

// ---- a pixel ---------------------------------------------------------------

fn run(input: PassInput) -> vec4<f32> {
	let pa = input.params[0];
	let pb = input.params[1];
	let pc = input.params[2];
	let pd = input.params[3];
	let cell = floor(input.pixel);
	let res = input.size;
	let e = input.time * max(pa.w, 0.05) + K_CYCLE - 2.5;
	let lap = floor(e / K_CYCLE);
	let ph = e - lap * K_CYCLE;
	let odd = lap - 2.0 * floor(lap * 0.5) > 0.5;
	var dir = 1.0;
	if (odd) {
		dir = -1.0;
	}
	g_thr = tk_bayer(cell + 2.0) * 0.96 + 0.02;
	tk_camera(cell, res, pb);
	let ro = g_ro;
	let rd = g_rd;

	// The crossing's round: the lamps blink, the gates fall, the train passes.
	let gate = smoothstep(1.0, 3.0, ph) * (1.0 - smoothstep(13.2, 15.0, ph));
	var lamps = vec2<f32>(0.0);
	if (ph < 13.6) {
		if (fract(ph * 1.15) < 0.5) {
			lamps.x = 1.0;
		} else {
			lamps.y = 1.0;
		}
	}
	let nose = -K_ENTER + (ph - K_ARRIVE) * K_SPEED;
	let passing = ph > K_ARRIVE && nose - K_TRAIN_L < K_ENTER;
	let train_y = K_FLOOR + K_BED_H + 0.06;

	// The still scenery, as kept.
	let st = zgx_ground_texel(vec2<i32>(cell));
	var sdep = 1e4;
	if (st.z > 0.0 && st.z < 1e3) {
		sdep = st.z;
	}
	g_best = sdep;
	g_id = -1;

	// The train: a long box, its doors, windows and stripe painted by where
	// along it the ray lands.
	if (passing) {
		let xa = dir * nose;
		let xb = dir * (nose - K_TRAIN_L);
		let lo = vec3<f32>(min(xa, xb), train_y, K_TRACK_Z - K_TRAIN_W);
		let hi = vec3<f32>(max(xa, xb), train_y + K_TRAIN_H, K_TRACK_Z + K_TRAIN_W);
		let ds = select(rd, vec3<f32>(1e-6), abs(rd) < vec3<f32>(1e-6));
		let ta = (lo - ro) / ds;
		let tb = (hi - ro) / ds;
		let tn = min(ta, tb);
		let tx = max(ta, tb);
		let t0 = max(max(tn.x, tn.y), tn.z);
		let t1 = min(min(tx.x, tx.y), tx.z);
		if (t0 < t1 && t0 > 0.0 && t0 < g_best) {
			let p = ro + rd * t0;
			let along = nose - dir * p.x;
			let yl = (p.y - train_y) / K_TRAIN_H;
			var m = 30;
			var det = 0.5 + 0.08 * sin(along * 9.0);
			var n = vec3<f32>(0.0, 0.0, -sign(rd.z));
			if (tn.x >= tn.y && tn.x >= tn.z) {
				// Its nose or its tail.
				n = vec3<f32>(-sign(rd.x), 0.0, 0.0);
				let zl = abs(p.z - K_TRACK_Z) / K_TRAIN_W;
				if (yl > 0.5 && yl < 0.8 && zl < 0.8) {
					m = 32;
				}
				if (yl > 0.38 && yl < 0.45) {
					m = 31;
				}
				if (yl > 0.19 && yl < 0.27 && abs(zl - 0.6) < 0.16) {
					m = 46;
					if (along > 1.0) {
						m = 48;
					}
				}
				if (yl < 0.14) {
					m = 33;
				}
			} else if (tn.y >= tn.z) {
				n = vec3<f32>(0.0, -sign(rd.y), 0.0);
				det = 0.25;
			} else {
				let cu = fract(along / K_CAR);
				let door = min(min(abs(cu - 0.14), abs(cu - 0.38)), min(abs(cu - 0.62), abs(cu - 0.86)));
				if (yl < 0.14) {
					// The underframe, with a bogie toward each end of a car.
					m = 33;
					if (abs(abs(cu - 0.5) - 0.32) < 0.07) {
						det = 0.95;
					}
				} else if (yl > 0.91) {
					det = 0.2;
				} else {
					if (yl > 0.38 && yl < 0.45) {
						m = 31;
					}
					if (yl > 0.87 && yl < 0.9) {
						m = 31;
					}
					if (yl > 0.5 && yl < 0.8 && cu > 0.03 && cu < 0.97) {
						if (door < 0.036) {
							if (door > 0.006 && door < 0.028 && yl > 0.56 && yl < 0.78) {
								m = 32;
							}
						} else if (door > 0.05) {
							m = 32;
						}
					}
					if (door > 0.034 && door < 0.041) {
						det = 0.22;
					}
				}
				if (cu < 0.012 || cu > 0.988) {
					m = 33;
					det = 0.3;
				}
				if (m == 32) {
					// People inside, against the light.
					let seat = tk_h31(vec3<f32>(floor(along * 11.0), lap, 2.0));
					if (seat > 0.5 && yl < 0.6 + 0.1 * seat) {
						m = 33;
						det = 0.9;
					}
				}
			}
			g_best = t0;
			g_id = 1;
			g_n = n;
			g_ao = 1.0;
			g_m = m;
			g_det = det;
		}
	}

	// The gates: a striped bar from each post, down across the road.
	for (var i = 0; i < N_XING; i = i + 1) {
		let c = K_XING[i];
		let sx = sign(c.x);
		let th = 1.42 * (1.0 - gate);
		let a = vec3<f32>(c.x - sx * 0.03, K_FLOOR + 0.46, c.y + c.z * 0.09);
		let b = a + vec3<f32>(-sx * cos(th), sin(th), 0.0) * 1.1;
		let t = tk_ray_bar(ro, rd, a, b, 0.024);
		if (t > 0.0 && t < g_best) {
			let p = ro + rd * t;
			let h = clamp(dot(p - a, b - a) / dot(b - a, b - a), 0.0, 1.0);
			g_best = t;
			g_id = 2;
			g_n = normalize(p - (a + (b - a) * h));
			g_ao = 1.0;
			g_det = 0.5;
			g_m = 34;
			if (fract(h * 5.5) > 0.5) {
				g_m = 35;
			}
		}
	}

	// People, and a dog: waiting at the gates, then crossing.
	if (pa.y > 0.5) {
		for (var i = 0; i < N_WHO; i = i + 1) {
			let who = K_WHO[i];
			let w = tk_path(i, ph);
			if (w.x > 900.0) {
				continue;
			}
			let stride = ph * 9.5 + f32(i) * 1.7;
			let at = vec3<f32>(w.x, tk_floor_y(w.y) + abs(sin(stride)) * 0.012 * w.w * who.y, w.y);
			var yaw = w.z;
			if (w.w < 0.01) {
				yaw = yaw + 0.12 * sin(e * 0.5 + f32(i) * 1.9);
			}
			let R = tk_yaw(yaw);
			g_who = vec4<f32>(who.x, who.y, who.z, stride);
			g_walk = w.w;
			if (who.x > 3.5) {
				tk_try(3, (ro - at) * R, rd * R, R, vec3<f32>(-0.2, -0.02, -0.1), vec3<f32>(0.26, 0.34, 0.1));
			} else {
				let s = who.y;
				tk_try(1, (ro - at) * R, rd * R, R, vec3<f32>(-0.2, -0.02, -0.2) * s, vec3<f32>(0.2, 0.72, 0.2) * s);
			}
		}
	}

	// What the ray met, lit: the evening's soft light, the lamps' warm pools,
	// and the train's windows spilling light over the road as it passes.
	var acc = vec3<f32>(0.0);
	var acc_a = 0.0;
	var rs = 10;
	var rc = N_PAL - 10;
	var lit_warm = false;
	let depth = g_best;
	if (depth < 1e3) {
		let p = ro + rd * depth;
		var l = 0.0;
		var m = 0;
		var ny = 0.0;
		var lw = 0.0;
		if (g_id >= 0) {
			let ndl = dot(g_n, normalize(vec3<f32>(-0.35, 0.65, 0.65)));
			l = 0.2 + 0.8 * clamp(ndl * 0.7 + 0.3, 0.0, 1.0);
			l = l * mix(0.4, 1.0, g_ao);
			l = l + (g_det - 0.5) * 0.4;
			m = g_m;
			ny = g_n.y;
			if (g_id == 1 || g_id == 3) {
				for (var i = 0; i < N_LIGHT; i = i + 1) {
					let lv = K_LIGHT[i].xyz - p;
					let ld = max(length(lv), 1e-4);
					lw = lw + K_LIGHT[i].w * (max(dot(g_n, lv / ld), 0.0) * 0.85 + 0.1) / (1.0 + ld * ld * 5.0);
				}
			}
		} else {
			l = st.x;
			m = i32(floor(st.y));
			ny = (fract(st.y) - 0.5) / 0.45;
			lw = st.w;
		}
		let side = p.z - (K_TRACK_Z + K_TRAIN_W);
		if (passing && side > 0.0 && side < 2.8 && m != 30 && m != 31) {
			let along = nose - dir * p.x;
			let beside = smoothstep(-0.4, 0.3, along) * (1.0 - smoothstep(K_TRAIN_L - 0.3, K_TRAIN_L + 0.4, along));
			lw = lw + beside * (0.24 + 0.1 * sin(along * 5.2)) * (0.4 + 0.6 * max(ny, 0.0)) / (1.0 + side * side * 2.0);
		}
		// The blossom stirs.
		if (m == 5 || m == 6) {
			l = l + 0.05 * sin(p.x * 9.0 + e * 1.3 + 2.0 * sin(p.y * 7.0 - e * 0.8));
		}
		var col = tk_colour(m, l, lamps, odd);
		rs = g_rs;
		rc = g_rc;
		let glows = m == 10 || m == 16 || m == 18 || m == 23 || m == 24 || m == 32 || m == 46 || m == 48;
		if (!glows) {
			lit_warm = lw > 0.03;
			col = col + vec3<f32>(0.95, 0.66, 0.34) * lw;
		}
		// The air between: far things sink into the evening's glow.
		var haze = smoothstep(7.5, 22.0, depth) * 0.72;
		if (glows) {
			haze = haze * 0.4;
		}
		acc = mix(col, K_PAL[6], haze);
		acc_a = 1.0;
	}
	let sdepth = depth * dot(rd, g_fwd);
	let ppx = res.y / (2.0 * K_TAN);

	// Glows, cut to dots: the lit crossing lamps, the street lamps, the
	// train's headlights.
	for (var i = 0; i < N_XING; i = i + 1) {
		let c = K_XING[i];
		if (c.z < 0.0 || ph >= 13.6) {
			continue;
		}
		var lx = -0.115;
		if (lamps.y > 0.5) {
			lx = 0.115;
		}
		let oo = ro - vec3<f32>(c.x + lx, K_FLOOR + 0.92, c.y + 0.06);
		let qb = dot(oo, rd);
		if (qb < 0.0 && -qb < depth + 0.05 && qb * qb - (dot(oo, oo) - 0.0196) > 0.0) {
			acc = K_PAL[P_RED + 2] * 0.5 + acc * 0.5;
			acc_a = 0.5 + acc_a * 0.5;
		}
	}
	for (var i = 0; i < N_LAMP; i = i + 1) {
		let c = K_LAMP[i];
		let oo = ro - vec3<f32>(c.x + c.w, K_FLOOR + c.z, c.y);
		let qb = dot(oo, rd);
		if (qb < 0.0 && -qb < depth + 0.1 && qb * qb - (dot(oo, oo) - 0.03) > 0.0) {
			acc = K_PAL[P_WARM + 3] * 0.3 + acc * 0.7;
			acc_a = 0.3 + acc_a * 0.7;
		}
	}
	if (passing) {
		let oo = ro - vec3<f32>(dir * (nose + 0.05), train_y + 0.34, K_TRACK_Z);
		let qb = dot(oo, rd);
		if (qb < 0.0 && -qb < depth + 0.3 && qb * qb - (dot(oo, oo) - 0.2) > 0.0) {
			acc = K_PAL[P_WARM + 4] * 0.34 + acc * 0.66;
			acc_a = 0.34 + acc_a * 0.66;
		}
	}

	// Petals on the air, a pixel or two each. A passing train sweeps them
	// along with it.
	let gust = dir * 9.0 * smoothstep(K_ARRIVE + 0.3, 13.0, ph);
	let petals = i32(clamp(pd.x, 0.0, 150.0));
	for (var i = 0; i < petals; i = i + 1) {
		let fi = f32(i);
		let b = tk_h13(fi * 1.7 + 11.0);
		let r = tk_h13(fi + 2.0);
		var p = vec3<f32>(b.x * 9.0, b.z * 3.4, -4.5 + b.y * 8.0);
		let fall = p.y - e * (0.1 + 0.16 * r.x);
		p.y = fall - 3.4 * floor(fall / 3.4) + K_FLOOR;
		let drift = p.x + e * 0.07 + gust + 0.22 * sin(e * (0.5 + r.z) + r.y * 40.0);
		p.x = drift - 9.0 * floor(drift / 9.0) - 4.5;
		p.z = p.z + 0.12 * sin(e * 0.6 + r.x * 30.0);
		let vv = p - ro;
		let zc = dot(vv, g_fwd);
		if (zc < sdepth && zc > 0.4) {
			let half = max(0.5, 0.017 / zc * ppx);
			let dx = res.x * 0.5 + dot(vv, g_right) / zc * ppx - (cell.x + 0.5);
			let dy = res.y * 0.5 - dot(vv, g_up) / zc * ppx - (cell.y + 0.5);
			if (max(abs(dx), abs(dy)) <= half) {
				let a = 0.95 * smoothstep(K_FLOOR, K_FLOOR + 0.25, p.y);
				let c = K_PAL[P_PINK + 3 + i32(floor(b.y * 2.99))];
				acc = c * a + acc * (1.0 - a);
				acc_a = a + acc_a * (1.0 - a);
				rs = P_PINK;
				rc = 6;
			}
		}
	}

	// Hard pixels: there or not, by a Bayer threshold; then the nearest of
	// the palette's colours.
	if (acc_a > g_thr) {
		return vec4<f32>(tk_nearest(acc / max(acc_a, 1e-4), cell, pa.z, rs, rc, lit_warm), 1.0);
	}
	return vec4<f32>(tk_sky(rd, cell, res, e), pc.x);
}

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

// Which of the three the scene plays (0 sunrise, 1 sunset, 2 night), and how
// far through its programme it is (0 to 1).
var<private> g_theme: i32;
var<private> g_prog: f32;

// A palette colour: the first ten are the sky's ramp, one ramp per theme.
fn tk_pal(i: i32) -> vec3<f32> {
	if (i < 10) {
		return K_SKY[g_theme * 10 + i];
	}
	return K_PAL[i];
}

// Who is out, by theme and round. 0 a parent, 1 their child, 2 someone with
// 3 a dog, 4 an office worker, 5 a student.
fn tk_cast(who: i32, round: i32) -> bool {
	if (g_theme == 1) {
		return true;
	}
	let walk = who == 2 || who == 3;
	if (g_theme == 0) {
		// Morning: work and school every round, the school run in most, the
		// dog's walk in the others.
		if (who >= 4) {
			return true;
		}
		let dog_round = round == 1 || round == 4 || round == 6;
		return walk == dog_round;
	}
	// Night: someone home late from the office; now and then the dog's last
	// walk; once, a student back from cram school.
	if (who == 4) {
		return round != 1 && round != 4;
	}
	if (walk) {
		return round == 1 || round == 4;
	}
	return who == 5 && round == 2;
}

// The rounds the cat comes in.
fn tk_cat_round(round: i32) -> bool {
	if (g_theme == 0) {
		return round == 4;
	}
	if (g_theme == 1) {
		return round == 1 || round == 4;
	}
	return round == 0 || round == 3 || round == 6;
}

fn tk_ramp(start: i32, count: i32, l0: f32) -> vec3<f32> {
	g_rs = start;
	g_rc = count;
	let l = clamp(l0, 0.0, 1.0) * f32(count - 1);
	let i = i32(floor(l));
	return mix(K_PAL[start + i], K_PAL[start + min(i + 1, count - 1)], fract(l));
}

// A material lit by `l`, through its ramp of the palette. `lamps` says which
// of the crossing's two lamps is lit; `livery` is the train's stripe: green
// (0), blue (1) or orange (2).
fn tk_colour(m: i32, l: f32, lamps: vec2<f32>, livery: i32) -> vec3<f32> {
	switch m {
		case 0: {
			if (g_theme == 2) {
				return tk_ramp(P_GREY, 6, l * 0.42 + 0.06);
			}
			return tk_ramp(P_GREY, 6, l * 0.46 + 0.17);
		}
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
		case 21: {
			if (g_theme == 2) {
				return tk_ramp(P_BLUE, 4, l * 0.3 + 0.08);
			}
			return tk_ramp(P_BLUE, 4, l * 0.35 + 0.4);
		}
		case 23, 48: { return tk_ramp(P_RED, 4, 0.82); }
		case 24: { return tk_ramp(P_BLUE, 4, 0.9); }
		case 30: { return tk_ramp(P_GREY, 6, l * 0.42 + 0.52); }
		case 31: {
			if (livery == 2) {
				return tk_ramp(P_WARM, 5, l * 0.25 + 0.42);
			}
			if (livery == 1) {
				return tk_ramp(P_BLUE, 4, l * 0.4 + 0.55);
			}
			return tk_ramp(P_GREEN, 5, l * 0.45 + 0.5);
		}
		case 32: {
			if (g_theme == 2) {
				return tk_ramp(P_WARM, 5, 0.9);
			}
			return tk_ramp(P_BLUE, 4, 0.82);
		}
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
		case 50: { return tk_ramp(P_PINK, 6, 0.66 + 0.2 * l); }
		case 52: { return tk_ramp(P_WARM, 5, 0.72 + 0.25 * l); }
		case 51: { return tk_ramp(P_GREEN, 5, 0.8); }
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
		let pc = tk_pal(i);
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
	let night = g_theme == 2;
	// The Skytree, in its own proportions: a lattice body, wide at the foot
	// and drawn in to a round shaft; the lower deck, three tiers that widen
	// upward; a slim neck; the small upper deck; the antenna in two steps,
	// a beacon blinking at the tip. By day it is pale, the sun glinting off
	// its decks; at night it is lit, blue then violet, with a light running
	// round each deck.
	let ty = up / 0.262;
	let from_tree = az + 0.064;
	let lower_deck = ty >= 0.52 && ty < 0.578;
	let upper_deck = ty >= 0.695 && ty < 0.728;
	let antenna = ty >= 0.775;
	var tree_half = 0.0052;
	if (ty < 0.52) {
		let to_shaft = 1.0 - ty / 0.52;
		tree_half = 0.0066 + 0.0074 * to_shaft * sqrt(to_shaft);
	} else if (ty < 0.538) {
		tree_half = 0.0086;
	} else if (ty < 0.558) {
		tree_half = 0.0102;
	} else if (ty < 0.578) {
		tree_half = 0.0116;
	} else if (ty < 0.59) {
		tree_half = 0.0078;
	} else if (ty < 0.695) {
		tree_half = 0.0052;
	} else if (ty < 0.712) {
		tree_half = 0.0068;
	} else if (ty < 0.728) {
		tree_half = 0.008;
	} else if (ty < 0.745) {
		tree_half = 0.0056;
	} else if (ty < 0.775) {
		tree_half = 0.004;
	} else if (ty < 0.875) {
		tree_half = 0.0027;
	} else {
		tree_half = 0.0015;
	}
	tree_half = tree_half * 1.35;
	if (ty > 0.0 && ty < 1.0 && abs(from_tree) < tree_half) {
		if (ty > 0.975) {
			if (sin(e * 2.4) > 0.0) {
				return tk_pal(P_RED + 2);
			}
			return tk_pal(P_RED + 1);
		}
		var glow = tk_pal(P_GREY + 5);
		var strut = tk_pal(P_GREY + 3);
		var deck = tk_pal(P_GREY + 1);
		var glint = tk_pal(9);
		var round_speed = 0.05;
		if (night) {
			glow = tk_pal(P_BLUE + 3);
			if (sin(e * 0.14) < 0.0) {
				glow = tk_pal(6);
			}
			strut = tk_pal(P_GREY + 5);
			deck = tk_pal(P_WARM + 3);
			glint = tk_pal(9);
			round_speed = 0.22;
		}
		let across = from_tree / tree_half;
		let row = floor(ty * 122.0);
		if (lower_deck || upper_deck) {
			if (fract(row * 0.5) < 0.25) {
				return glow;
			}
			let round_it = fract(e * round_speed + ty * 3.0) * 2.0 - 1.0;
			if (abs(across - round_it) < 0.3) {
				return glint;
			}
			return deck;
		}
		if (antenna) {
			if (abs(ty - 0.875) < 0.006) {
				return strut;
			}
			return glow;
		}
		if (ty >= 0.578 && abs(across) > 0.55) {
			return glow;
		}
		if (ty >= 0.578) {
			return strut;
		}
		if (abs(across) > 0.72) {
			return glow;
		}
		if (fract(ty * 13.0 + from_tree * 60.0) < 0.5 == fract(ty * 13.0 - from_tree * 60.0) < 0.5) {
			return strut;
		}
		return glow;
	}
	// The city, near: blocks along the horizon. At night its windows are
	// lit; by day a few catch the sun.
	var lit_share = 0.93;
	var far_lit_share = 0.95;
	if (night) {
		lit_share = 0.78;
		far_lit_share = 0.84;
	}
	let block = floor(az * 30.0);
	var roof = 0.015 + 0.04 * tk_h31(vec3<f32>(block, 1.0, 5.0));
	if (tk_h31(vec3<f32>(block, 2.0, 9.0)) > 0.8) {
		roof = roof + 0.05;
	}
	if (up < roof) {
		let wx = floor(fract(az * 30.0) * 4.0);
		if (up > 0.0 && wx > 0.5 && tk_h31(vec3<f32>(block * 4.0 + wx, floor(up * 300.0), 4.0)) > lit_share) {
			return tk_pal(P_WARM + 3);
		}
		return tk_pal(2);
	}
	// And farther: taller towers, paler.
	let far_at = az * 13.0 + 3.3;
	let far_block = floor(far_at);
	var far_roof = 0.045 + 0.075 * tk_h31(vec3<f32>(far_block, 6.0, 2.0));
	if (tk_h31(vec3<f32>(far_block, 3.0, 4.0)) > 0.7) {
		far_roof = far_roof + 0.05;
	}
	let far_edge = abs(fract(far_at) - 0.5);
	if (up < far_roof && far_edge < 0.42) {
		let wx = floor(fract(far_at) * 7.0);
		let wy = floor(up * 210.0);
		if (far_edge < 0.34 && up < far_roof - 0.008 && tk_h31(vec3<f32>(far_block * 7.0 + wx, wy, 8.0)) > far_lit_share) {
			if (night) {
				return tk_pal(P_WARM + 2);
			}
			return tk_pal(8);
		}
		return tk_pal(3);
	}
	// A plane on its way in to Haneda: by day its body and a thinning trail,
	// at night a red light and a white one that winks.
	let per_cell = 2.0 * K_TAN / res.y;
	let here = vec2<f32>(az, up);
	let plane = vec2<f32>(1.5 - 3.0 * fract(e / 70.0), 0.34 - 0.05 * fract(e / 70.0));
	let from_plane = (here - plane) / per_cell;
	if (abs(from_plane.y + from_plane.x * 0.0167) < 0.5) {
		if (night) {
			if (abs(from_plane.x) < 0.5) {
				return tk_pal(P_RED + 2);
			}
			if (abs(from_plane.x - 2.0) < 0.5 && fract(e * 0.9) < 0.25) {
				return tk_pal(9);
			}
		} else {
			if (from_plane.x > -0.5 && from_plane.x < 1.5) {
				return tk_pal(P_GREY + 5);
			}
			if (from_plane.x > 1.5 && from_plane.x < 46.0 && tk_bayer(cell) > from_plane.x / 46.0) {
				return tk_pal(9);
			}
		}
	}
	var li = clamp(0.93 - 2.1 * up, 0.08, 0.97);
	if (night) {
		// A shooting star, now and then; the moon, a crescent; stars.
		let turn = floor(e / 19.0);
		let since = e - turn * 19.0;
		if (since < 0.8) {
			let head = vec2<f32>(-0.9 + 1.8 * tk_h31(vec3<f32>(turn, 1.0, 3.0)), 0.36 + 0.08 * tk_h31(vec3<f32>(turn, 2.0, 3.0)))
				+ vec2<f32>(0.5, -0.16) * since;
			let back = here - head;
			let along_tail = clamp(dot(back, vec2<f32>(-0.95, 0.31)), 0.0, 0.11 * (1.0 - since));
			if (length(back - vec2<f32>(-0.95, 0.31) * along_tail) < per_cell * 0.7) {
				return tk_pal(9);
			}
		}
		let mc = vec2<f32>(floor(res.x * 0.62), floor(res.y * 0.15));
		let mr = max(4.5, res.y * 0.042);
		if (length(cell - mc) < mr && length(cell - mc - vec2<f32>(mr * 0.45, -mr * 0.3)) > mr * 0.95) {
			return tk_pal(9);
		}
		if (up > 0.16) {
			let star = tk_h31(vec3<f32>(cell.x, cell.y, 7.0));
			if (star > 0.9935 && sin(e * (0.6 + star * 40.0) + star * 90.0) > -0.6) {
				return tk_pal(8);
			}
		}
		li = clamp(0.92 - 2.7 * up, 0.06, 0.95);
		li = li + 0.1 * (1.0 - smoothstep(mr, mr * 3.2, length(cell - mc)));
	} else {
		// Birds: a few going home at sunset, more of them about at sunrise.
		var flocks = 1;
		if (g_theme == 0) {
			flocks = 2;
		}
		for (var f = 0; f < flocks; f = f + 1) {
			let ff = f32(f);
			let flock = vec2<f32>((-1.4 + 2.8 * fract(e / (47.0 - 14.0 * ff) + 0.4 * ff)) * (1.0 - 2.0 * ff), 0.27 + 0.06 * ff + 0.02 * sin(e * 0.4));
			for (var i = 0; i < 4; i = i + 1) {
				let fi = f32(i);
				let bird = flock + vec2<f32>(-0.035 * fi * (1.0 - 2.0 * ff), 0.013 * fi * (1.0 - 2.0 * f32(i & 1)));
				let at = round((here - bird) / per_cell);
				var wing = 0.0;
				if (sin(e * 7.0 + fi * 1.7) > 0.0) {
					wing = 1.0;
				}
				if ((at.x == 0.0 && at.y == 0.0) || (abs(at.x) == 1.0 && at.y == wing)) {
					return tk_pal(P_GREY + 1);
				}
			}
		}
		// The sun: rising through the programme at sunrise, sinking at
		// sunset.
		var sun = vec2<f32>(0.1, 0.17 - 0.11 * g_prog);
		if (g_theme == 0) {
			sun = vec2<f32>(-0.01, 0.045 + 0.13 * g_prog);
		}
		let from_sun = length(here - sun);
		if (from_sun < 0.034) {
			return tk_pal(9);
		}
		li = li + (0.3 + 0.03 * sin(e * 0.35)) * (1.0 - smoothstep(0.034, 0.26, from_sun));
	}
	// Long cloud, lit from below.
	let cloud = 0.7 * tk_noise(vec3<f32>(az * 1.5 / (up + 0.35) + e * 0.006, up * 21.0, 3.0))
		+ 0.3 * tk_noise(vec3<f32>(az * 6.0 + e * 0.01, up * 46.0, 5.0));
	if (up > 0.03 && cloud > 0.56) {
		li = li + 0.12 + 0.6 * (cloud - 0.56);
	}
	li = min(li, 0.99);
	let wi = li * 9.0;
	var idx = i32(floor(wi));
	if (fract(wi) > tk_bayer(cell)) {
		idx = idx + 1;
	}
	return tk_pal(min(idx, 9));
}

// ---- a pixel ---------------------------------------------------------------

fn run(input: PassInput) -> vec4<f32> {
	let pa = input.params[0];
	let pb = input.params[1];
	let pc = input.params[2];
	let pd = input.params[3];
	let cell = floor(input.pixel);
	let res = input.size;
	let e = input.time * max(pa.w, 0.05) + pd.y + K_CYCLE - 2.5;
	let lap = floor(e / K_CYCLE);
	let ph = e - lap * K_CYCLE;
	// Seven rounds make a theme's programme, five minutes long. A commuter
	// train and a Shinkansen take turns, from one side and the other; at
	// night one commuter train gives way to a freight train.
	g_theme = i32(clamp(pc.z, 0.0, 2.0) + 0.5);
	let night = g_theme == 2;
	let first = lap - 1.0;
	let round = i32(first - 7.0 * floor(first / 7.0));
	g_prog = (f32(round) + ph / K_CYCLE) / 7.0;
	let bullet = (round & 1) == 1;
	let freight = night && round == 4;
	let odd = (((round + 1) / 2) & 1) == 1;
	var livery = (round / 2) % 3;
	var train_speed = K_SPEED;
	var train_len = K_TRAIN_L;
	var arrive = K_ARRIVE;
	if (bullet) {
		livery = 1;
		train_speed = 19.0;
		train_len = 56.0;
		arrive = 6.0;
	}
	var lamp_light = 0.3;
	var lamp_halo = 0.06;
	var train_glow = 0.03;
	var haze_amount = 0.55;
	if (g_theme == 0) {
		lamp_light = 0.12;
		haze_amount = 0.7;
	} else if (night) {
		lamp_light = 1.0;
		lamp_halo = 0.3;
		train_glow = 0.24;
		haze_amount = 0.72;
	}
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
	let nose = -K_ENTER + (ph - arrive) * train_speed;
	let passing = ph > arrive && nose - train_len < K_ENTER;
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
		let xb = dir * (nose - train_len);
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
			var det = 0.5;
			var n = vec3<f32>(0.0, 0.0, -sign(rd.z));
			// (A Shinkansen's nose and tail slope away: above that line
			// there is no train.)
			let from_end = min(along, train_len - along);
			let seen = !bullet || from_end > 3.4 || yl < 0.3 + 0.7 * sqrt(max(from_end, 0.0) / 3.4);
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
					// People inside, against the light: shoulders and a head.
					let seat = tk_h31(vec3<f32>(floor(along * 4.0), lap, 2.0));
					let off = abs(fract(along * 4.0) - 0.5);
					let tall = 0.03 * seat;
					if (seat > 0.45 && ((off < 0.36 && yl < 0.6 + tall) || (off < 0.16 && yl < 0.665 + tall))) {
						m = 33;
						det = 0.9;
					} else if (fract(along * 0.55 + yl * 1.3) < 0.09) {
						// (The glass catches the sky, in slanting bands.)
						m = 24;
					}
				}
				if (freight) {
					// Containers on flat wagons, behind a blue locomotive.
					let wagon = floor(along / K_CAR);
					let pick = tk_h31(vec3<f32>(wagon, 7.0, 3.0));
					m = 39;
					if (pick < 0.3) {
						m = 38;
					} else if (pick < 0.55) {
						m = 36;
					} else if (pick < 0.75) {
						m = 6;
					}
					det = 0.42 + 0.16 * step(0.5, fract(along * 5.0));
					if (cu > 0.47 && cu < 0.53) {
						m = 33;
						det = 0.3;
					}
					if (wagon < 0.5) {
						m = 38;
						det = 0.5;
						if (yl > 0.58 && yl < 0.8 && cu < 0.2) {
							m = 32;
						}
						if (yl > 0.36 && yl < 0.44) {
							m = 12;
						}
					}
					if (yl < 0.2) {
						m = 33;
						det = 0.5;
						if (abs(abs(cu - 0.5) - 0.32) < 0.07) {
							det = 0.95;
						}
					}
					if (cu < 0.03 || cu > 0.97 || (yl > 0.86 && wagon > 0.5)) {
						m = 33;
						det = 0.3;
					}
				}
				if (bullet) {
					// White, a blue line along it, a row of small windows.
					m = 49;
					det = 0.5;
					if (yl > 0.36 && yl < 0.43) {
						m = 31;
					}
					if (yl > 0.56 && yl < 0.7 && from_end > 4.6 && fract(along * 1.5) > 0.32) {
						m = 32;
					}
					if (yl < 0.16) {
						m = 30;
						det = 0.3;
					}
					if (fract(along / 8.0) < 0.01) {
						det = 0.25;
					}
				}
			}
			if (seen) {
				g_best = t0;
				g_id = 1;
				g_n = n;
				g_ao = 1.0;
				g_m = m;
				g_det = det;
			}
		}
	}

	// The gates: a striped bar from each post, down across the road.
	for (var i = 0; i < N_XING; i = i + 1) {
		let c = K_XING[i];
		let sx = sign(c.x);
		let th = 1.42 * (1.0 - gate) + 0.07 * exp(-max(ph - 2.9, 0.0) * 2.6) * abs(sin((ph - 2.9) * 9.0)) * step(2.9, ph);
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
			if (!tk_cast(i, round)) {
				continue;
			}
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
			if (!night) {
				l = st.x * 1.06 + 0.05;
			}
			m = i32(floor(st.y));
			ny = (fract(st.y) - 0.5) / 0.45;
			lw = st.w;
		}
		lw = lw * lamp_light;
		// (A window lit only at night.)
		if (m == 53) {
			m = select(21, 10, night);
		}
		let side = p.z - (K_TRACK_Z + K_TRAIN_W);
		if (passing && side > 0.0 && side < 2.8 && m != 30 && m != 31) {
			let along = nose - dir * p.x;
			let beside = smoothstep(-0.4, 0.3, along) * (1.0 - smoothstep(train_len - 0.3, train_len + 0.4, along));
			lw = lw + beside * train_glow * (0.4 + 0.6 * max(ny, 0.0)) / (1.0 + side * side * 2.0);
		}
		// The blossom stirs, and tosses as the train goes by.
		let wind = smoothstep(arrive + 0.3, arrive + 2.4, ph) * (1.0 - smoothstep(11.5, 15.0, ph));
		if (m == 5 || m == 6) {
			l = l + (0.05 + 0.09 * wind) * sin(p.x * 9.0 + e * (1.3 + 4.0 * wind) + 2.0 * sin(p.y * 7.0 - e * 0.8));
		}
		var col = tk_colour(m, l, lamps, livery);
		rs = g_rs;
		rc = g_rc;
		let glows = m == 10 || m == 16 || m == 18 || m == 23 || m == 24 || m == 32 || m == 46 || m == 48 || m == 50 || m == 51 || m == 52;
		if (!glows) {
			lit_warm = lw > 0.03;
			col = col + vec3<f32>(0.95, 0.66, 0.34) * lw;
		}
		// The air between: far things sink into the evening's glow.
		var haze = smoothstep(7.5, 22.0, depth) * haze_amount;
		if (glows) {
			haze = haze * 0.4;
		}
		acc = mix(col, tk_pal(6), haze);
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
			acc = tk_pal(P_RED + 2) * 0.5 + acc * 0.5;
			acc_a = 0.5 + acc_a * 0.5;
		}
	}
	for (var i = 0; i < N_LAMP; i = i + 1) {
		let c = K_LAMP[i];
		let oo = ro - vec3<f32>(c.x + c.w, K_FLOOR + c.z, c.y);
		let qb = dot(oo, rd);
		if (qb < 0.0 && -qb < depth + 0.1 && qb * qb - (dot(oo, oo) - 0.03) > 0.0) {
			acc = tk_pal(P_WARM + 3) * lamp_halo + acc * (1.0 - lamp_halo);
			acc_a = lamp_halo + acc_a * (1.0 - lamp_halo);
		}
	}
	if (passing) {
		let oo = ro - vec3<f32>(dir * (nose + 0.05), train_y + 0.34, K_TRACK_Z);
		let qb = dot(oo, rd);
		if (qb < 0.0 && -qb < depth + 0.3 && qb * qb - (dot(oo, oo) - 0.2) > 0.0) {
			acc = tk_pal(P_WARM + 4) * 0.34 + acc * 0.66;
			acc_a = 0.34 + acc_a * 0.66;
		}
	}

	// A black cat comes along the road once the people have gone, sits a
	// while to look at you, and goes on its way.
	if (pa.y > 0.5 && tk_cat_round(round) && ph > 17.0 && ph < 35.5) {
		let sits = ph > 23.5 && ph < 27.5;
		var cat_x = -4.2 + (ph - 17.0) * 0.55;
		if (ph > 23.5) {
			cat_x = -0.625 + max(ph - 27.5, 0.0) * 0.55;
		}
		let vv = vec3<f32>(cat_x, K_FLOOR, 2.85) - ro;
		let zc = dot(vv, g_fwd);
		if (zc < sdepth + 0.2) {
			let u = (cell.x + 0.5 - res.x * 0.5) / ppx * zc - dot(vv, g_right);
			var v = (res.y * 0.5 - (cell.y + 0.5)) / ppx * zc - dot(vv, g_up);
			// Its coat: 0 black, 1 where the light catches it, 9 an eye.
			var fur = -1;
			if (sits) {
				// Seen from the front: a pear of a body, the tail laid round its
				// feet and flicking at the tip, a wide head, tall ears.
				let flick = 0.045 * max(sin(e * 2.2), 0.0);
				if (length(vec2<f32>(u / (0.07 + 0.035 * smoothstep(0.2, 0.0, v)), (v - 0.11) / 0.12)) < 1.0) {
					fur = 0;
					if (abs(u) < 0.02 && v > 0.1 && v < 0.19) {
						fur = 1;
					}
				}
				if (u > -0.21 && u < -0.03 && v > 0.0 && v < 0.035 + flick * smoothstep(-0.13, -0.21, u)) {
					fur = 0;
				}
				let head = vec2<f32>(u, v - 0.275);
				if (length(head / vec2<f32>(0.075, 0.062)) < 1.0) {
					fur = 0;
					if (abs(abs(u) - 0.032) < 0.011 && abs(head.y - 0.008) < 0.009 && fract(e * 0.31) > 0.06) {
						fur = 9;
					}
				}
				if (head.y > 0.03 && head.y < 0.115 - abs(abs(u) - 0.048) * 2.6) {
					fur = 0;
				}
			} else {
				// Seen from the side, walking: it bobs, its legs swing in
				// pairs, and its tail is carried high, curling at the tip.
				let pace = sin(e * 9.0);
				v = v - 0.008 * abs(pace);
				if (length(vec2<f32>(u / 0.135, (v - 0.155) / 0.058)) < 1.0) {
					fur = 0;
					if (v > 0.185 && abs(u) < 0.08) {
						fur = 1;
					}
				}
				let fore = abs(u - 0.085 - 0.035 * pace) < 0.014 || abs(u + 0.095 + 0.035 * pace) < 0.014;
				let hind = abs(u - 0.06 + 0.035 * pace) < 0.014 || abs(u + 0.07 - 0.035 * pace) < 0.014;
				if (v > -0.008 && v < 0.13 && (fore || hind)) {
					fur = 0;
				}
				let head = vec2<f32>(u - 0.165, v - 0.215);
				if (length(head / vec2<f32>(0.062, 0.054)) < 1.0) {
					fur = 0;
					if (abs(head.x - 0.03) < 0.01 && abs(head.y - 0.008) < 0.009) {
						fur = 9;
					}
				}
				if (head.y > 0.03 && head.y < 0.105 - abs(abs(head.x - 0.005) - 0.034) * 2.6) {
					fur = 0;
				}
				let tail = vec2<f32>(u + 0.125, v - 0.17);
				let lean = 0.12 * sin(e * 2.0);
				let rise = clamp(tail.y, 0.0, 0.2);
				let curl = -0.05 - lean * rise * 5.0 + 0.9 * rise * rise * 5.0 * 0.2;
				if (tail.y > -0.01 && tail.y < 0.2 && abs(tail.x - curl * rise * 5.0) < 0.016) {
					fur = 0;
				}
			}
			if (fur >= 0) {
				acc = tk_pal(P_GREY + min(fur, 1));
				rs = P_GREY;
				rc = 6;
				if (fur == 9) {
					acc = tk_pal(P_WARM + 3);
					rs = P_WARM;
					rc = 5;
				}
				acc_a = 1.0;
				lit_warm = false;
			}
		}
	}

	// Sunrise: three sparrows peck about on the road, and are off.
	if (g_theme == 0 && (round == 0 || round == 3 || round == 6) && ph > 18.0 && ph < 38.5) {
		for (var i = 0; i < 3; i = i + 1) {
			let fi = f32(i);
			let away = max(ph - 34.5 - 0.3 * fi, 0.0);
			let hop = floor(ph * 0.8 + fi * 0.37);
			let hopping = max(sin((ph * 0.8 + fi * 0.37) * 6.2832), 0.0) * 0.03;
			var bird = vec3<f32>(-0.55 + 0.5 * fi + 0.12 * (tk_h31(vec3<f32>(hop, fi, 4.0)) - 0.5), K_FLOOR + hopping, 2.35 + 0.2 * fi);
			bird = bird + vec3<f32>((1.4 * (fi - 1.0) + 0.5) * away, 1.1 * away, 0.0);
			let vv = bird - ro;
			let zc = dot(vv, g_fwd);
			if (zc < sdepth + 0.2) {
				let u = ((cell.x + 0.5 - res.x * 0.5) / ppx * zc - dot(vv, g_right)) * (1.0 - 2.0 * f32(i & 1));
				let v = (res.y * 0.5 - (cell.y + 0.5)) / ppx * zc - dot(vv, g_up);
				var feather = -1;
				let pecks = away == 0.0 && sin(ph * 5.0 + fi * 2.0) > 0.55;
				var head = vec2<f32>(0.04, 0.075);
				if (pecks) {
					head = vec2<f32>(0.055, 0.03);
				}
				if (length(vec2<f32>(u / 0.048, (v - 0.04) / 0.032)) < 1.0) {
					feather = 2;
					if (v < 0.035) {
						feather = 4;
					}
				}
				if (length(vec2<f32>(u, v) - head) < 0.024) {
					feather = 1;
				}
				if (u < -0.035 && u > -0.085 && abs(v - 0.05) < 0.012) {
					feather = 1;
				}
				if (away > 0.0 && abs(u) < 0.07 && abs(v - 0.06 - 0.05 * sin(e * 16.0) * abs(u) / 0.07) < 0.012) {
					feather = 2;
				}
				if (feather >= 0) {
					acc = tk_pal(P_WOOD + feather);
					acc_a = 1.0;
					rs = P_WOOD;
					rc = 5;
					lit_warm = false;
				}
			}
		}
	}

	// Night: moths about the near street lamp.
	if (night) {
		let lamp = K_LAMP[0];
		for (var i = 0; i < 5; i = i + 1) {
			let fi = f32(i);
			let turn = e * (1.3 + 0.35 * fi) + fi * 2.1;
			let moth = vec3<f32>(lamp.x + lamp.w, K_FLOOR + lamp.z - 0.06, lamp.y)
				+ vec3<f32>(cos(turn), 0.5 * sin(turn * 1.7 + fi), sin(turn)) * (0.1 + 0.035 * fi);
			let vv = moth - ro;
			let zc = dot(vv, g_fwd);
			if (zc < sdepth) {
				let dx = res.x * 0.5 + dot(vv, g_right) / zc * ppx - (cell.x + 0.5);
				let dy = res.y * 0.5 - dot(vv, g_up) / zc * ppx - (cell.y + 0.5);
				if (max(abs(dx), abs(dy)) <= 0.5) {
					acc = tk_pal(P_WARM + 4);
					acc_a = 1.0;
					rs = P_WARM;
					rc = 5;
				}
			}
		}
	}

	// The child's red balloon gets away, and climbs out of the picture.
	if (pa.y > 0.5 && g_theme == 1 && round == 5 && ph > 16.0 && ph < 31.0) {
		let rise = ph - 16.0;
		let balloon = vec3<f32>(-0.2 + 0.25 * sin(rise * 0.6) + 0.07 * rise, K_FLOOR + 0.62 + 0.24 * rise + 0.03 * sin(rise * 2.3), 1.65);
		let vv = balloon - ro;
		let zc = dot(vv, g_fwd);
		if (zc < sdepth) {
			let u = (cell.x + 0.5 - res.x * 0.5) / ppx * zc - dot(vv, g_right);
			let v = (res.y * 0.5 - (cell.y + 0.5)) / ppx * zc - dot(vv, g_up);
			var skin = -1;
			if (v < -0.085 && v > -0.3 && abs(u - 0.02 * sin(v * 30.0 + e * 3.0)) < 0.008) {
				skin = 0;
			}
			if (length(vec2<f32>(u / 0.075, v / 0.09)) < 1.0) {
				skin = 2;
				if (length(vec2<f32>(u + 0.025, v - 0.035)) < 0.022) {
					skin = 3;
				}
			}
			if (skin >= 0) {
				acc = tk_pal(P_RED + skin);
				if (skin == 0) {
					acc = tk_pal(P_GREY + 4);
				}
				acc_a = 1.0;
				rs = P_RED;
				rc = 4;
				lit_warm = false;
			}
		}
	}

	// Petals on the air, a pixel or two each. A passing train sweeps them
	// along with it.
	// The train's wind, and in the last round a gust down the street.
	var blow = dir * 1.7 * smoothstep(arrive + 0.3, arrive + 2.4, ph) * (1.0 - smoothstep(11.5, 15.0, ph));
	if (bullet) {
		blow = blow * 1.8;
	}
	if (g_theme == 1 && round == 6) {
		blow = blow + 3.2 * smoothstep(23.0, 26.0, ph) * (1.0 - smoothstep(30.0, 34.0, ph));
	}
	// Each falls from a tree's canopy to the ground, drifting, and starts
	// again: petals from the sakura, leaves green or yellowed from the others.
	let petals = i32(clamp(pd.x, 0.0, 150.0));
	for (var i = 0; i < petals; i = i + 1) {
		let fi = f32(i);
		let b = tk_h13(fi * 1.7 + 11.0);
		let r = tk_h13(fi + 2.0);
		// (Two in three from the two sakura by the road, where they show.)
		var tree = i % 2;
		if (i % 3 == 2) {
			tree = i % N_TREE;
		}
		let canopy = K_TREE_B[tree];
		let reach = (canopy.w - 0.2) / 1.3;
		let start = canopy.xyz + (b - vec3<f32>(0.5)) * vec3<f32>(1.5, 0.5, 1.2) * reach;
		let height = start.y - K_FLOOR;
		let fallen = fract(e * (0.07 + 0.06 * r.x) / height * 2.0 + r.y);
		var p = start;
		p.y = start.y - fallen * height;
		p.x = p.x + (0.35 * (r.z - 0.3) + blow) * fallen * height + 0.14 * sin(e * (0.5 + r.z) + r.y * 40.0);
		p.z = p.z + 0.12 * sin(e * 0.6 + r.x * 30.0);
		let vv = p - ro;
		let zc = dot(vv, g_fwd);
		if (zc < sdepth && zc > 0.4) {
			let half = max(0.5, 0.019 / zc * ppx);
			let turn = 0.35 + 0.65 * abs(sin(e * (1.4 + 2.0 * r.x) + r.z * 20.0));
			let dx = res.x * 0.5 + dot(vv, g_right) / zc * ppx - (cell.x + 0.5);
			let dy = res.y * 0.5 - dot(vv, g_up) / zc * ppx - (cell.y + 0.5);
			if (abs(dx) <= half && abs(dy) <= max(0.5, half * turn)) {
				let a = 0.95 * smoothstep(0.0, 0.06, fallen) * (1.0 - smoothstep(0.9, 1.0, fallen));
				var c = tk_pal(P_PINK + 3 + i32(floor(b.y * 2.99)));
				var family = P_PINK;
				var shades = 6;
				if (K_TREE_T[tree].w > 0.5 || b.x > 0.82) {
					c = tk_pal(P_GREEN + 3 + i32(floor(b.y * 1.99)));
					family = P_GREEN;
					shades = 5;
					if (b.z > 0.55) {
						c = tk_pal(P_WARM + 3);
						family = P_WARM;
					}
				}
				acc = c * a + acc * (1.0 - a);
				acc_a = a + acc_a * (1.0 - a);
				rs = family;
				rc = shades;
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

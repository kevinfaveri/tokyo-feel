const K_TAN: f32 = 0.26794919;
const K_PI: f32 = 3.14159265;
const K_FLOOR: f32 = -0.75;
// The track runs along x at this z; the road runs along z at x = 0.
const K_TRACK_Z: f32 = -0.5;
const K_RAIL: f32 = 0.27;
const K_BED: f32 = 0.8;
const K_BED_H: f32 = 0.07;
const K_ROAD: f32 = 0.95;
const K_WALK: f32 = 1.55;
// One round of the crossing, in seconds: the gates fall, a train passes,
// the gates rise, people cross.
const K_CYCLE: f32 = 44.0;

// Where each family of colours starts in the palette, and how many it has.
const P_GREY: i32 = 10;
const P_PINK: i32 = 16;
const P_GREEN: i32 = 22;
const P_WOOD: i32 = 27;
const P_WARM: i32 = 32;
const P_RED: i32 = 37;
const P_BLUE: i32 = 41;

var<private> g_near: f32;
var<private> g_mat: i32;
var<private> g_thr: f32;
var<private> g_ro: vec3<f32>;
var<private> g_rd: vec3<f32>;
var<private> g_fwd: vec3<f32>;
var<private> g_right: vec3<f32>;
var<private> g_up: vec3<f32>;

/*TABLES*/

// ---- hashes and noise ------------------------------------------------------

fn tk_h31(p: vec3<f32>) -> f32 {
	var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
	q = q + dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

fn tk_h13(x: f32) -> vec3<f32> {
	var p = fract(vec3<f32>(x) * vec3<f32>(0.1031, 0.1030, 0.0973));
	p = p + dot(p, p.yzx + 33.33);
	return fract((p.xxy + p.yzz) * p.zyx);
}

fn tk_noise(p: vec3<f32>) -> f32 {
	let i = floor(p);
	let f = fract(p);
	let u = f * f * (3.0 - 2.0 * f);
	let a = mix(tk_h31(i), tk_h31(i + vec3<f32>(1.0, 0.0, 0.0)), u.x);
	let b = mix(tk_h31(i + vec3<f32>(0.0, 1.0, 0.0)), tk_h31(i + vec3<f32>(1.0, 1.0, 0.0)), u.x);
	let c = mix(tk_h31(i + vec3<f32>(0.0, 0.0, 1.0)), tk_h31(i + vec3<f32>(1.0, 0.0, 1.0)), u.x);
	let d = mix(tk_h31(i + vec3<f32>(0.0, 1.0, 1.0)), tk_h31(i + vec3<f32>(1.0, 1.0, 1.0)), u.x);
	return mix(mix(a, b, u.y), mix(c, d, u.y), u.z);
}

// Cells: the distance to the nearest of the points scattered one per cell.
fn tk_cells(p: vec3<f32>, seed: f32) -> f32 {
	let ip = floor(p);
	var nearest = 9.0;
	for (var z = -1; z <= 1; z = z + 1) {
		for (var y = -1; y <= 1; y = y + 1) {
			for (var x = -1; x <= 1; x = x + 1) {
				let c = ip + vec3<f32>(f32(x), f32(y), f32(z));
				let o = vec3<f32>(tk_h31(c + seed), tk_h31(c.yzx + seed + 17.0), tk_h31(c.zxy + seed + 31.0));
				nearest = min(nearest, length(p - (c + o)));
			}
		}
	}
	return nearest;
}

const K_BAYER: array<f32, 16> = array<f32, 16>(0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
fn tk_bayer(c: vec2<f32>) -> f32 {
	let x = u32(abs(c.x)) & 3u;
	let y = u32(abs(c.y)) & 3u;
	return (K_BAYER[y * 4u + x] + 0.5) / 16.0;
}

// ---- shapes ----------------------------------------------------------------

fn tk_ell(p: vec3<f32>, c: vec3<f32>, r: vec3<f32>) -> f32 {
	let q = p - c;
	let k0 = length(q / r);
	let k1 = length(q / (r * r));
	if (k1 < 1e-9) {
		return -min(r.x, min(r.y, r.z));
	}
	return k0 * (k0 - 1.0) / k1;
}

fn tk_cap(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, ra: f32, rb: f32) -> f32 {
	let ab = b - a;
	let ap = p - a;
	let h = clamp(dot(ap, ab) / dot(ab, ab), 0.0, 1.0);
	return length(ap - ab * h) - (ra + (rb - ra) * h);
}

fn tk_box(p: vec3<f32>, half: vec3<f32>) -> f32 {
	let q = abs(p) - half;
	return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn tk_smin(a: f32, b: f32, k: f32) -> f32 {
	let h = max(k - abs(a - b), 0.0) / k;
	return min(a, b) - h * h * k * 0.25;
}

// ---- the camera: still, at the roadside, looking across the track ----------

fn tk_camera(cell: vec2<f32>, res: vec2<f32>, pb: vec4<f32>) {
	let aspect = res.x / max(res.y, 1.0);
	let dist = 6.4 * max(pb.z, 0.2) * max(1.0, 1.25 / aspect);
	g_ro = vec3<f32>(0.0, 0.05, dist);
	let tgt = vec3<f32>(0.0, 0.15 + pb.w, 0.0);
	g_fwd = normalize(tgt - g_ro);
	g_right = normalize(cross(g_fwd, vec3<f32>(0.0, 1.0, 0.0)));
	g_up = cross(g_right, g_fwd);
	let ndc = vec2<f32>((cell.x + 0.5) / res.x * 2.0 - 1.0, 1.0 - (cell.y + 0.5) / res.y * 2.0);
	g_rd = normalize(g_fwd + g_right * (ndc.x * aspect * K_TAN) + g_up * (ndc.y * K_TAN));
}

// The ground's height: flat, with the track's bed raised a little.
fn tk_floor_y(z: f32) -> f32 {
	return K_FLOOR + K_BED_H * (1.0 - smoothstep(K_BED, K_BED + 0.35, abs(z - K_TRACK_Z)));
}

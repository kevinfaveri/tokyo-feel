-- The crossing, as WGSL: three sources.
--
--   GROUND  a pass drawn once (and again when the box changes size): the
--           still scenery (road, track, the crossing's posts, trees, houses,
--           poles and wires), kept per art pixel as light, material, depth
--           and warm light.
--   LIVE    a pass drawn every frame, at one texel per art pixel: what moves
--           (the train, the gates, people and a dog, the lamps, petals) over
--           GROUND's pixels, lit, cut to hard pixels and snapped to the
--           palette; then the sky.
--   SHOW    the layer shader that scales LIVE up, nearest-neighbour.
--
-- Forms are sculpted in 3D, each surface point lit and coloured through a
-- ramp, the picture drawn small, translucent things cut to on/off pixels by
-- a Bayer threshold, every pixel the nearest of a small palette. Generated
-- by src/build.py from src/*.wgsl: edit those, not this file.
--
-- params[0] = { -, people (0 or 1), dither, speed }
-- params[1] = { alpha, brightness, zoom, lift }
-- params[2] = { the sky's alpha, how muted (0 to 1), the theme (0 sunrise, 1 sunset, 2 night), - }
-- params[3] = { how many petals, the programme's seconds when the scene was built, -, - }
local M = {}

M.GROUND = [==[
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

const N_PAL: i32 = 45;
const K_PAL: array<vec3<f32>, 45> = array<vec3<f32>, 45>(
	vec3<f32>(0.2314, 0.3098, 0.5412),
	vec3<f32>(0.3216, 0.3412, 0.6039),
	vec3<f32>(0.451, 0.3804, 0.6431),
	vec3<f32>(0.6039, 0.4353, 0.6588),
	vec3<f32>(0.7686, 0.498, 0.6275),
	vec3<f32>(0.8902, 0.5843, 0.5647),
	vec3<f32>(0.9569, 0.6784, 0.4863),
	vec3<f32>(0.9765, 0.7843, 0.4667),
	vec3<f32>(0.9922, 0.8784, 0.5569),
	vec3<f32>(1.0, 0.9529, 0.7686),
	vec3<f32>(0.0784, 0.0824, 0.1216),
	vec3<f32>(0.149, 0.1569, 0.2118),
	vec3<f32>(0.2431, 0.2549, 0.3216),
	vec3<f32>(0.3882, 0.4039, 0.4745),
	vec3<f32>(0.6039, 0.6196, 0.6745),
	vec3<f32>(0.8471, 0.8588, 0.8784),
	vec3<f32>(0.2275, 0.1098, 0.2),
	vec3<f32>(0.4196, 0.1843, 0.3216),
	vec3<f32>(0.6588, 0.3098, 0.4706),
	vec3<f32>(0.8706, 0.5255, 0.6392),
	vec3<f32>(0.9686, 0.7216, 0.7882),
	vec3<f32>(0.9922, 0.902, 0.9176),
	vec3<f32>(0.0588, 0.1333, 0.098),
	vec3<f32>(0.1098, 0.2392, 0.1647),
	vec3<f32>(0.1843, 0.3882, 0.251),
	vec3<f32>(0.3529, 0.5804, 0.3412),
	vec3<f32>(0.6118, 0.7804, 0.4863),
	vec3<f32>(0.1216, 0.0784, 0.0627),
	vec3<f32>(0.2314, 0.149, 0.1059),
	vec3<f32>(0.3843, 0.251, 0.1647),
	vec3<f32>(0.5765, 0.4157, 0.2627),
	vec3<f32>(0.7882, 0.6353, 0.451),
	vec3<f32>(0.3529, 0.2039, 0.0745),
	vec3<f32>(0.6588, 0.3804, 0.1098),
	vec3<f32>(0.9098, 0.6039, 0.1725),
	vec3<f32>(0.9843, 0.8275, 0.3725),
	vec3<f32>(1.0, 0.9647, 0.7686),
	vec3<f32>(0.2392, 0.051, 0.0706),
	vec3<f32>(0.5412, 0.102, 0.1176),
	vec3<f32>(0.8471, 0.2039, 0.1647),
	vec3<f32>(1.0, 0.5412, 0.3608),
	vec3<f32>(0.0627, 0.1373, 0.2471),
	vec3<f32>(0.1137, 0.2588, 0.451),
	vec3<f32>(0.2275, 0.4549, 0.6902),
	vec3<f32>(0.498, 0.7059, 0.8627)
);

const K_SKY: array<vec3<f32>, 30> = array<vec3<f32>, 30>(
	vec3<f32>(0.3098, 0.4706, 0.6902),
	vec3<f32>(0.4, 0.5647, 0.7608),
	vec3<f32>(0.5137, 0.6588, 0.8235),
	vec3<f32>(0.6392, 0.749, 0.8745),
	vec3<f32>(0.7647, 0.8275, 0.902),
	vec3<f32>(0.8784, 0.8588, 0.8863),
	vec3<f32>(0.9608, 0.8667, 0.8275),
	vec3<f32>(0.9843, 0.8902, 0.7529),
	vec3<f32>(0.9922, 0.9412, 0.8118),
	vec3<f32>(1.0, 0.9843, 0.9176),
	vec3<f32>(0.2314, 0.3098, 0.5412),
	vec3<f32>(0.3216, 0.3412, 0.6039),
	vec3<f32>(0.451, 0.3804, 0.6431),
	vec3<f32>(0.6039, 0.4353, 0.6588),
	vec3<f32>(0.7686, 0.498, 0.6275),
	vec3<f32>(0.8902, 0.5843, 0.5647),
	vec3<f32>(0.9569, 0.6784, 0.4863),
	vec3<f32>(0.9765, 0.7843, 0.4667),
	vec3<f32>(0.9922, 0.8784, 0.5569),
	vec3<f32>(1.0, 0.9529, 0.7686),
	vec3<f32>(0.0431, 0.051, 0.1216),
	vec3<f32>(0.0784, 0.0902, 0.2),
	vec3<f32>(0.1216, 0.1373, 0.3137),
	vec3<f32>(0.1882, 0.1882, 0.4314),
	vec3<f32>(0.2941, 0.2471, 0.5255),
	vec3<f32>(0.4588, 0.3216, 0.6039),
	vec3<f32>(0.6588, 0.4157, 0.6392),
	vec3<f32>(0.851, 0.5412, 0.651),
	vec3<f32>(0.949, 0.702, 0.6549),
	vec3<f32>(0.9843, 0.8627, 0.7529)
);

const N_XING: i32 = 4;
const K_XING: array<vec4<f32>, 4> = array<vec4<f32>, 4>(
	vec4<f32>(-1.25, 0.85, 1.0, 0.0),
	vec4<f32>(1.25, 0.85, 1.0, 0.0),
	vec4<f32>(-1.25, -1.85, -1.0, 0.0),
	vec4<f32>(1.25, -1.85, -1.0, 0.0)
);

const N_POLE: i32 = 2;
const K_POLE: array<vec4<f32>, 2> = array<vec4<f32>, 2>(
	vec4<f32>(-2.3, -1.62, 2.35, 0.2),
	vec4<f32>(2.75, -1.62, 2.35, 0.2)
);

const N_WIRE: i32 = 36;
const K_WIRE_A: array<vec3<f32>, 36> = array<vec3<f32>, 36>(
	vec3<f32>(-9.0, 1.52, -1.8),
	vec3<f32>(-6.7667, 1.3422, -1.8),
	vec3<f32>(-4.5333, 1.3422, -1.8),
	vec3<f32>(-2.3, 1.52, -1.8),
	vec3<f32>(-1.4583, 1.4422, -1.8),
	vec3<f32>(-0.6167, 1.3956, -1.8),
	vec3<f32>(0.225, 1.38, -1.8),
	vec3<f32>(1.0667, 1.3956, -1.8),
	vec3<f32>(1.9083, 1.4422, -1.8),
	vec3<f32>(2.75, 1.52, -1.8),
	vec3<f32>(4.8333, 1.3422, -1.8),
	vec3<f32>(6.9167, 1.3422, -1.8),
	vec3<f32>(-9.0, 1.52, -1.44),
	vec3<f32>(-6.7667, 1.2889, -1.44),
	vec3<f32>(-4.5333, 1.2889, -1.44),
	vec3<f32>(-2.3, 1.52, -1.44),
	vec3<f32>(-1.4583, 1.4089, -1.44),
	vec3<f32>(-0.6167, 1.3422, -1.44),
	vec3<f32>(0.225, 1.32, -1.44),
	vec3<f32>(1.0667, 1.3422, -1.44),
	vec3<f32>(1.9083, 1.4089, -1.44),
	vec3<f32>(2.75, 1.52, -1.44),
	vec3<f32>(4.8333, 1.2889, -1.44),
	vec3<f32>(6.9167, 1.2889, -1.44),
	vec3<f32>(-9.0, 1.22, -1.62),
	vec3<f32>(-6.7667, 0.9356, -1.62),
	vec3<f32>(-4.5333, 0.9356, -1.62),
	vec3<f32>(-2.3, 1.22, -1.62),
	vec3<f32>(-1.4583, 1.0756, -1.62),
	vec3<f32>(-0.6167, 0.9889, -1.62),
	vec3<f32>(0.225, 0.96, -1.62),
	vec3<f32>(1.0667, 0.9889, -1.62),
	vec3<f32>(1.9083, 1.0756, -1.62),
	vec3<f32>(2.75, 1.22, -1.62),
	vec3<f32>(4.8333, 0.9356, -1.62),
	vec3<f32>(6.9167, 0.9356, -1.62)
);
const K_WIRE_B: array<vec3<f32>, 36> = array<vec3<f32>, 36>(
	vec3<f32>(-6.7667, 1.3422, -1.8),
	vec3<f32>(-4.5333, 1.3422, -1.8),
	vec3<f32>(-2.3, 1.52, -1.8),
	vec3<f32>(-1.4583, 1.4422, -1.8),
	vec3<f32>(-0.6167, 1.3956, -1.8),
	vec3<f32>(0.225, 1.38, -1.8),
	vec3<f32>(1.0667, 1.3956, -1.8),
	vec3<f32>(1.9083, 1.4422, -1.8),
	vec3<f32>(2.75, 1.52, -1.8),
	vec3<f32>(4.8333, 1.3422, -1.8),
	vec3<f32>(6.9167, 1.3422, -1.8),
	vec3<f32>(9.0, 1.52, -1.8),
	vec3<f32>(-6.7667, 1.2889, -1.44),
	vec3<f32>(-4.5333, 1.2889, -1.44),
	vec3<f32>(-2.3, 1.52, -1.44),
	vec3<f32>(-1.4583, 1.4089, -1.44),
	vec3<f32>(-0.6167, 1.3422, -1.44),
	vec3<f32>(0.225, 1.32, -1.44),
	vec3<f32>(1.0667, 1.3422, -1.44),
	vec3<f32>(1.9083, 1.4089, -1.44),
	vec3<f32>(2.75, 1.52, -1.44),
	vec3<f32>(4.8333, 1.2889, -1.44),
	vec3<f32>(6.9167, 1.2889, -1.44),
	vec3<f32>(9.0, 1.52, -1.44),
	vec3<f32>(-6.7667, 0.9356, -1.62),
	vec3<f32>(-4.5333, 0.9356, -1.62),
	vec3<f32>(-2.3, 1.22, -1.62),
	vec3<f32>(-1.4583, 1.0756, -1.62),
	vec3<f32>(-0.6167, 0.9889, -1.62),
	vec3<f32>(0.225, 0.96, -1.62),
	vec3<f32>(1.0667, 0.9889, -1.62),
	vec3<f32>(1.9083, 1.0756, -1.62),
	vec3<f32>(2.75, 1.22, -1.62),
	vec3<f32>(4.8333, 0.9356, -1.62),
	vec3<f32>(6.9167, 0.9356, -1.62),
	vec3<f32>(9.0, 1.22, -1.62)
);

const N_LAMP: i32 = 6;
const K_LAMP: array<vec4<f32>, 6> = array<vec4<f32>, 6>(
	vec4<f32>(-1.3, 1.62, 1.5, 0.3),
	vec4<f32>(1.32, -2.3, 1.5, -0.3),
	vec4<f32>(-1.32, -5.2, 1.5, 0.3),
	vec4<f32>(1.32, -8.0, 1.5, -0.3),
	vec4<f32>(-1.32, -11.0, 1.5, 0.3),
	vec4<f32>(1.32, -14.0, 1.5, -0.3)
);

const K_VEND: vec2<f32> = vec2<f32>(1.76, 1.42);

const N_LIGHT: i32 = 7;
const K_LIGHT: array<vec4<f32>, 7> = array<vec4<f32>, 7>(
	vec4<f32>(-1.0, 0.7, 1.62, 1.0),
	vec4<f32>(1.02, 0.7, -2.3, 1.0),
	vec4<f32>(-1.02, 0.7, -5.2, 1.0),
	vec4<f32>(1.02, 0.7, -8.0, 1.0),
	vec4<f32>(-1.02, 0.7, -11.0, 1.0),
	vec4<f32>(1.02, 0.7, -14.0, 1.0),
	vec4<f32>(1.76, -0.33, 1.72, 0.45)
);

const N_TREE: i32 = 8;
const K_TREE_T: array<vec4<f32>, 8> = array<vec4<f32>, 8>(
	vec4<f32>(-1.98, 1.05, 0.95, 0.0),
	vec4<f32>(2.08, 0.75, 1.0, 0.0),
	vec4<f32>(-4.3, -3.4, 1.1, 0.0),
	vec4<f32>(-1.45, -3.7, 0.85, 1.0),
	vec4<f32>(1.5, -3.6, 0.9, 1.0),
	vec4<f32>(3.95, -3.5, 1.1, 0.0),
	vec4<f32>(-3.1, -5.6, 1.0, 0.0),
	vec4<f32>(5.6, -5.2, 1.1, 1.0)
);
const K_TREE_L: array<vec4<f32>, 8> = array<vec4<f32>, 8>(
	vec4<f32>(-2.06, 0.2, 1.05, 0.0),
	vec4<f32>(2.18, 0.25, 0.75, 0.0),
	vec4<f32>(-4.25, 0.35, -3.4, 0.0),
	vec4<f32>(-1.45, 0.1, -3.7, 0.0),
	vec4<f32>(1.54, 0.15, -3.6, 0.0),
	vec4<f32>(3.89, 0.35, -3.5, 0.0),
	vec4<f32>(-3.1, 0.25, -5.6, 0.0),
	vec4<f32>(5.6, 0.35, -5.2, 0.0)
);
const K_TREE_BR: array<vec4<f32>, 24> = array<vec4<f32>, 24>(
	vec4<f32>(-1.6236, 0.4479, 1.0089, 0.0),
	vec4<f32>(-2.193, 0.4566, 1.3209, 0.0),
	vec4<f32>(-2.3111, 0.6019, 0.7113, 0.0),
	vec4<f32>(2.6157, 0.8143, 0.6849, 0.0),
	vec4<f32>(2.0677, 0.5397, 0.9737, 0.0),
	vec4<f32>(1.9812, 0.7615, 0.4136, 0.0),
	vec4<f32>(-3.6011, 0.6585, -3.3314, 0.0),
	vec4<f32>(-4.359, 0.8973, -2.9592, 0.0),
	vec4<f32>(-4.4893, 1.0925, -3.8181, 0.0),
	vec4<f32>(-1.0627, 0.3306, -3.6726, 0.0),
	vec4<f32>(-1.5314, 0.4999, -3.5064, 0.0),
	vec4<f32>(-1.6888, 0.5402, -3.8949, 0.0),
	vec4<f32>(2.0045, 0.3541, -3.6299, 0.0),
	vec4<f32>(1.4204, 0.4546, -3.4235, 0.0),
	vec4<f32>(1.3725, 0.3177, -3.8711, 0.0),
	vec4<f32>(4.2291, 0.8971, -3.5194, 0.0),
	vec4<f32>(3.7088, 0.6556, -3.2452, 0.0),
	vec4<f32>(3.6724, 0.7537, -3.7968, 0.0),
	vec4<f32>(-2.7657, 0.493, -5.6055, 0.0),
	vec4<f32>(-3.202, 0.513, -5.2626, 0.0),
	vec4<f32>(-3.2125, 0.612, -5.8851, 0.0),
	vec4<f32>(6.1225, 1.0313, -5.2429, 0.0),
	vec4<f32>(5.4533, 0.5773, -4.8878, 0.0),
	vec4<f32>(5.4628, 1.0328, -5.6303, 0.0)
);
const K_BLOB: array<vec4<f32>, 48> = array<vec4<f32>, 48>(
	vec4<f32>(-1.6236, 0.5479, 1.0089, 0.4248),
	vec4<f32>(-1.9413, 0.7545, 1.2928, 0.4615),
	vec4<f32>(-2.193, 0.5566, 1.3209, 0.4732),
	vec4<f32>(-2.4695, 0.6195, 1.0631, 0.5404),
	vec4<f32>(-2.3111, 0.7019, 0.7113, 0.5611),
	vec4<f32>(-1.7198, 0.6511, 0.7539, 0.407),
	vec4<f32>(2.6157, 0.9143, 0.6849, 0.3971),
	vec4<f32>(2.5408, 0.7146, 1.0271, 0.4722),
	vec4<f32>(2.0677, 0.6397, 0.9737, 0.3882),
	vec4<f32>(1.8566, 0.8105, 0.7167, 0.4473),
	vec4<f32>(1.9812, 0.8615, 0.4136, 0.4266),
	vec4<f32>(2.3966, 0.9408, 0.4269, 0.4711),
	vec4<f32>(-3.6011, 0.7585, -3.3314, 0.4954),
	vec4<f32>(-3.9992, 0.9532, -3.1261, 0.5841),
	vec4<f32>(-4.359, 0.9973, -2.9592, 0.5673),
	vec4<f32>(-4.7561, 1.0085, -3.4983, 0.5003),
	vec4<f32>(-4.4893, 1.1925, -3.8181, 0.5272),
	vec4<f32>(-4.0335, 1.0648, -3.668, 0.5665),
	vec4<f32>(-1.0627, 0.4306, -3.6726, 0.4191),
	vec4<f32>(-1.311, 0.4926, -3.5347, 0.3783),
	vec4<f32>(-1.5314, 0.5999, -3.5064, 0.3088),
	vec4<f32>(-1.7557, 0.636, -3.6447, 0.3252),
	vec4<f32>(-1.6888, 0.6402, -3.8949, 0.3506),
	vec4<f32>(-1.2574, 0.4764, -3.8774, 0.4029),
	vec4<f32>(2.0045, 0.4541, -3.6299, 0.4344),
	vec4<f32>(1.7655, 0.5794, -3.4155, 0.3463),
	vec4<f32>(1.4204, 0.5546, -3.4235, 0.3505),
	vec4<f32>(1.1242, 0.6564, -3.5723, 0.3915),
	vec4<f32>(1.3725, 0.4177, -3.8711, 0.3984),
	vec4<f32>(1.8588, 0.6967, -3.8466, 0.4203),
	vec4<f32>(4.2291, 0.9971, -3.5194, 0.4918),
	vec4<f32>(4.1386, 0.7612, -3.2727, 0.4321),
	vec4<f32>(3.7088, 0.7556, -3.2452, 0.4295),
	vec4<f32>(3.5078, 1.1172, -3.4324, 0.4854),
	vec4<f32>(3.6724, 0.8537, -3.7968, 0.4467),
	vec4<f32>(4.0945, 1.1766, -3.9066, 0.4421),
	vec4<f32>(-2.7657, 0.593, -5.6055, 0.4564),
	vec4<f32>(-2.8094, 0.6196, -5.273, 0.4209),
	vec4<f32>(-3.202, 0.613, -5.2626, 0.5321),
	vec4<f32>(-3.5337, 0.9873, -5.609, 0.3824),
	vec4<f32>(-3.2125, 0.712, -5.8851, 0.4908),
	vec4<f32>(-2.9617, 0.8976, -5.9298, 0.5031),
	vec4<f32>(6.1225, 1.1313, -5.2429, 0.4371),
	vec4<f32>(5.7618, 1.0149, -4.7989, 0.5368),
	vec4<f32>(5.4533, 0.6773, -4.8878, 0.4875),
	vec4<f32>(5.2217, 0.9924, -5.1119, 0.4468),
	vec4<f32>(5.4628, 1.1328, -5.6303, 0.4755),
	vec4<f32>(5.8751, 0.7713, -5.4153, 0.4614)
);
const K_TREE_B: array<vec4<f32>, 8> = array<vec4<f32>, 8>(
	vec4<f32>(-2.108, 0.7225, 1.05, 1.435),
	vec4<f32>(2.24, 0.745, 0.75, 1.37),
	vec4<f32>(-4.22, 0.9275, -3.4, 1.565),
	vec4<f32>(-1.45, 0.485, -3.7, 1.11),
	vec4<f32>(1.564, 0.5625, -3.6, 1.175),
	vec4<f32>(3.854, 0.9, -3.5, 1.5),
	vec4<f32>(-3.1, 0.745, -5.6, 1.37),
	vec4<f32>(5.6, 0.8725, -5.2, 1.435)
);

const N_BUSH: i32 = 12;
const K_BUSH: array<vec4<f32>, 12> = array<vec4<f32>, 12>(
	vec4<f32>(-2.4, -0.6285, 0.52, 0.27),
	vec4<f32>(-1.82, -0.66, 0.5, 0.2),
	vec4<f32>(1.8, -0.651, 0.5, 0.22),
	vec4<f32>(2.55, -0.624, 0.47, 0.28),
	vec4<f32>(-1.9, -0.642, -1.78, 0.24),
	vec4<f32>(-2.65, -0.615, -1.82, 0.3),
	vec4<f32>(1.9, -0.633, -1.8, 0.26),
	vec4<f32>(2.9, -0.615, -1.78, 0.3),
	vec4<f32>(-3.5, -0.615, -1.9, 0.3),
	vec4<f32>(3.6, -0.633, -1.9, 0.26),
	vec4<f32>(-3.3, -0.615, 0.6, 0.3),
	vec4<f32>(3.3, -0.615, 0.55, 0.3)
);

const N_HOUSE: i32 = 10;
const K_HOUSE_C: array<vec4<f32>, 10> = array<vec4<f32>, 10>(
	vec4<f32>(-2.75, -4.3, 0.95, 0.6),
	vec4<f32>(2.7, -4.4, 0.85, 0.6),
	vec4<f32>(-6.0, -7.2, 1.4, 0.7),
	vec4<f32>(4.9, -7.6, 1.5, 0.7),
	vec4<f32>(-2.7, -7.3, 0.95, 0.9),
	vec4<f32>(2.75, -7.9, 0.95, 1.0),
	vec4<f32>(-2.9, -10.8, 1.05, 1.2),
	vec4<f32>(2.95, -11.4, 1.05, 1.2),
	vec4<f32>(-3.1, -15.0, 1.15, 1.6),
	vec4<f32>(3.1, -15.6, 1.15, 1.6)
);
const K_HOUSE_H: array<vec4<f32>, 10> = array<vec4<f32>, 10>(
	vec4<f32>(0.95, 0.42, 8.0, 0.0),
	vec4<f32>(1.35, 0.4, 8.0, 0.0),
	vec4<f32>(2.5, 0.0, 20.0, 0.0),
	vec4<f32>(3.0, 0.0, 20.0, 0.0),
	vec4<f32>(1.9, 0.0, 20.0, 0.0),
	vec4<f32>(2.5, 0.0, 8.0, 0.0),
	vec4<f32>(3.2, 0.0, 20.0, 0.0),
	vec4<f32>(2.4, 0.0, 20.0, 0.0),
	vec4<f32>(3.9, 0.0, 20.0, 0.0),
	vec4<f32>(3.3, 0.0, 8.0, 0.0)
);

const N_WHO: i32 = 6;
const N_KEY: i32 = 9;
const K_WHO: array<vec4<f32>, 6> = array<vec4<f32>, 6>(
	vec4<f32>(0.0, 1.0, 38.0, 0.0),
	vec4<f32>(2.0, 0.62, 38.0, 0.0),
	vec4<f32>(0.0, 0.95, 40.0, 0.0),
	vec4<f32>(4.0, 1.0, 43.0, 0.0),
	vec4<f32>(3.0, 1.02, 41.0, 0.0),
	vec4<f32>(1.0, 0.9, 38.0, 0.0)
);
const K_PATH: array<vec4<f32>, 54> = array<vec4<f32>, 54>(
	vec4<f32>(0.0, -0.5, 1.55, -1.5708),
	vec4<f32>(15.4, -0.5, 1.55, -1.5708),
	vec4<f32>(23.4, -0.5, -2.7, -1.5708),
	vec4<f32>(32.6, -5.2, -2.7, -1.5708),
	vec4<f32>(32.7, -3.3, 2.1, -1.5708),
	vec4<f32>(37.3, -0.5, 2.1, -1.5708),
	vec4<f32>(38.3, -0.5, 1.55, -1.5708),
	vec4<f32>(38.3, -0.5, 1.55, -1.5708),
	vec4<f32>(44.0, -0.5, 1.55, -1.5708),
	vec4<f32>(0.0, -0.23, 1.65, -1.5708),
	vec4<f32>(15.65, -0.23, 1.65, -1.5708),
	vec4<f32>(23.65, -0.23, -2.6, -1.5708),
	vec4<f32>(32.85, -4.93, -2.6, -1.5708),
	vec4<f32>(32.95, -3.03, 2.2, -1.5708),
	vec4<f32>(37.55, -0.23, 2.2, -1.5708),
	vec4<f32>(38.55, -0.23, 1.65, -1.5708),
	vec4<f32>(38.55, -0.23, 1.65, -1.5708),
	vec4<f32>(44.0, -0.23, 1.65, -1.5708),
	vec4<f32>(0.0, 0.45, 1.72, -1.5708),
	vec4<f32>(15.7, 0.45, 1.72, -1.5708),
	vec4<f32>(23.9, 0.5, -2.72, -1.5708),
	vec4<f32>(33.0, 5.3, -2.72, -1.5708),
	vec4<f32>(33.1, 3.4, 2.25, -1.5708),
	vec4<f32>(38.3, 0.45, 2.25, -1.5708),
	vec4<f32>(39.1, 0.45, 1.72, -1.5708),
	vec4<f32>(39.1, 0.45, 1.72, -1.5708),
	vec4<f32>(44.0, 0.45, 1.72, -1.5708),
	vec4<f32>(0.0, 0.75, 1.6, -1.5708),
	vec4<f32>(15.8, 0.75, 1.6, -1.5708),
	vec4<f32>(24.0, 0.8, -2.84, -1.5708),
	vec4<f32>(33.1, 5.6, -2.84, -1.5708),
	vec4<f32>(33.2, 3.7, 2.13, -1.5708),
	vec4<f32>(38.4, 0.75, 2.13, -1.5708),
	vec4<f32>(39.2, 0.75, 1.6, -1.5708),
	vec4<f32>(39.2, 0.75, 1.6, -1.5708),
	vec4<f32>(44.0, 0.75, 1.6, -1.5708),
	vec4<f32>(0.0, 0.35, -2.35, 1.5708),
	vec4<f32>(15.5, 0.35, -2.35, 1.5708),
	vec4<f32>(23.5, 0.35, 2.2, 1.5708),
	vec4<f32>(28.8, 3.5, 2.25, 1.5708),
	vec4<f32>(28.9, -5.3, -2.72, 1.5708),
	vec4<f32>(33.0, -5.3, -2.72, 1.5708),
	vec4<f32>(42.5, 0.35, -2.72, 1.5708),
	vec4<f32>(43.2, 0.35, -2.35, 1.5708),
	vec4<f32>(44.0, 0.35, -2.35, 1.5708),
	vec4<f32>(0.0, -0.35, -2.5, 1.5708),
	vec4<f32>(15.9, -0.35, -2.5, 1.5708),
	vec4<f32>(24.0, -0.35, 2.15, 1.5708),
	vec4<f32>(29.4, -3.5, 2.2, 1.5708),
	vec4<f32>(29.5, 5.3, -2.78, 1.5708),
	vec4<f32>(32.0, 5.3, -2.78, 1.5708),
	vec4<f32>(41.6, -0.35, -2.78, 1.5708),
	vec4<f32>(42.2, -0.35, -2.5, 1.5708),
	vec4<f32>(44.0, -0.35, -2.5, 1.5708)
);


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
		var share = 0.011;
		if (m == 3) {
			share = 0.04;
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
			// (10 is lit at any hour, 53 only at night.)
			let lit = tk_h31(vec3<f32>(floor(gx), floor(gy), f32(obj) + 3.0));
			if (lit > 0.88) {
				m = 10;
			} else if (lit > 0.42) {
				m = 53;
			}
		}
	}
	// The vending machine's lit front, and what it sells.
	if (m == 17 && n.z > 0.6 && abs(q.x) < 0.16 && q.y > -0.2 && q.y < 0.3) {
		// Three shelves of four drinks, in front of a lit panel.
		m = 16;
		let across = (q.x + 0.16) * 12.5;
		let shelf = (q.y + 0.2) * 6.0;
		if (fract(shelf) < 0.12) {
			m = 17;
		} else if (fract(shelf) < 0.74 && abs(fract(across) - 0.5) < 0.3) {
			let pick = (i32(floor(across)) + 2 * i32(floor(shelf))) % 3;
			m = 23;
			if (pick == 1) {
				m = 51;
			} else if (pick == 2) {
				m = 10;
			}
		}
	}
	// Its coin slot and its tray.
	if (m == 17 && n.z > 0.6 && abs(q.x) < 0.16) {
		if (q.y < -0.24 && q.y > -0.33 && q.x > 0.06 && q.x < 0.13) {
			m = 18;
		}
		if (q.y < -0.4 && q.y > -0.5 && abs(q.x) < 0.11) {
			m = 13;
		}
	}
	// Every other bush is in flower.
	var bloom = false;
	if (m == 6 && obj >= 100 && ((obj - 100) & 1) == 1) {
		bloom = tk_cells(p * 16.0, 9.0) < 0.3;
	}

	let grain = tk_grain(m, p);
	// The evening's light: soft, from the front and above.
	let ndl = dot(n, normalize(vec3<f32>(-0.5, 0.55, 0.6)));
	var l = 0.2 + 0.8 * clamp(ndl * 0.7 + 0.3, 0.0, 1.0);
	l = l * mix(0.4, 1.0, ao);
	l = l + (grain - 0.5) * 0.4;
	if (petal || bloom) {
		m = 5;
		l = 0.78 + 0.2 * grain;
	}
	// Some of what has fallen is leaves, green or yellowed.
	if (petal) {
		let leaf = tk_h31(floor(vec3<f32>(p.x * 27.0, 8.0, p.z * 27.0)));
		if (leaf > 0.8) {
			m = 44;
		} else if (leaf > 0.58) {
			m = 6;
			l = 0.9;
		}
	}
	// Warm light pooling under the lamps and by the vending machine.
	var lw = 0.0;
	if (m != 10 && m != 16 && m != 18 && m != 23 && m != 24 && m != 50 && m != 51 && m != 53) {
		for (var i = 0; i < N_LIGHT; i = i + 1) {
			let lv = K_LIGHT[i].xyz - p;
			let ld = max(length(lv), 1e-4);
			lw = lw + K_LIGHT[i].w * (max(dot(n, lv / ld), 0.0) * 0.85 + 0.1) / (1.0 + ld * ld * 5.0);
		}
	}
	return vec4<f32>(clamp(l, 0.0, 1.0), f32(m) + clamp(n.y * 0.45 + 0.5, 0.02, 0.98), t, lw);
}
]==]

M.LIVE = [==[
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

const N_PAL: i32 = 45;
const K_PAL: array<vec3<f32>, 45> = array<vec3<f32>, 45>(
	vec3<f32>(0.2314, 0.3098, 0.5412),
	vec3<f32>(0.3216, 0.3412, 0.6039),
	vec3<f32>(0.451, 0.3804, 0.6431),
	vec3<f32>(0.6039, 0.4353, 0.6588),
	vec3<f32>(0.7686, 0.498, 0.6275),
	vec3<f32>(0.8902, 0.5843, 0.5647),
	vec3<f32>(0.9569, 0.6784, 0.4863),
	vec3<f32>(0.9765, 0.7843, 0.4667),
	vec3<f32>(0.9922, 0.8784, 0.5569),
	vec3<f32>(1.0, 0.9529, 0.7686),
	vec3<f32>(0.0784, 0.0824, 0.1216),
	vec3<f32>(0.149, 0.1569, 0.2118),
	vec3<f32>(0.2431, 0.2549, 0.3216),
	vec3<f32>(0.3882, 0.4039, 0.4745),
	vec3<f32>(0.6039, 0.6196, 0.6745),
	vec3<f32>(0.8471, 0.8588, 0.8784),
	vec3<f32>(0.2275, 0.1098, 0.2),
	vec3<f32>(0.4196, 0.1843, 0.3216),
	vec3<f32>(0.6588, 0.3098, 0.4706),
	vec3<f32>(0.8706, 0.5255, 0.6392),
	vec3<f32>(0.9686, 0.7216, 0.7882),
	vec3<f32>(0.9922, 0.902, 0.9176),
	vec3<f32>(0.0588, 0.1333, 0.098),
	vec3<f32>(0.1098, 0.2392, 0.1647),
	vec3<f32>(0.1843, 0.3882, 0.251),
	vec3<f32>(0.3529, 0.5804, 0.3412),
	vec3<f32>(0.6118, 0.7804, 0.4863),
	vec3<f32>(0.1216, 0.0784, 0.0627),
	vec3<f32>(0.2314, 0.149, 0.1059),
	vec3<f32>(0.3843, 0.251, 0.1647),
	vec3<f32>(0.5765, 0.4157, 0.2627),
	vec3<f32>(0.7882, 0.6353, 0.451),
	vec3<f32>(0.3529, 0.2039, 0.0745),
	vec3<f32>(0.6588, 0.3804, 0.1098),
	vec3<f32>(0.9098, 0.6039, 0.1725),
	vec3<f32>(0.9843, 0.8275, 0.3725),
	vec3<f32>(1.0, 0.9647, 0.7686),
	vec3<f32>(0.2392, 0.051, 0.0706),
	vec3<f32>(0.5412, 0.102, 0.1176),
	vec3<f32>(0.8471, 0.2039, 0.1647),
	vec3<f32>(1.0, 0.5412, 0.3608),
	vec3<f32>(0.0627, 0.1373, 0.2471),
	vec3<f32>(0.1137, 0.2588, 0.451),
	vec3<f32>(0.2275, 0.4549, 0.6902),
	vec3<f32>(0.498, 0.7059, 0.8627)
);

const K_SKY: array<vec3<f32>, 30> = array<vec3<f32>, 30>(
	vec3<f32>(0.3098, 0.4706, 0.6902),
	vec3<f32>(0.4, 0.5647, 0.7608),
	vec3<f32>(0.5137, 0.6588, 0.8235),
	vec3<f32>(0.6392, 0.749, 0.8745),
	vec3<f32>(0.7647, 0.8275, 0.902),
	vec3<f32>(0.8784, 0.8588, 0.8863),
	vec3<f32>(0.9608, 0.8667, 0.8275),
	vec3<f32>(0.9843, 0.8902, 0.7529),
	vec3<f32>(0.9922, 0.9412, 0.8118),
	vec3<f32>(1.0, 0.9843, 0.9176),
	vec3<f32>(0.2314, 0.3098, 0.5412),
	vec3<f32>(0.3216, 0.3412, 0.6039),
	vec3<f32>(0.451, 0.3804, 0.6431),
	vec3<f32>(0.6039, 0.4353, 0.6588),
	vec3<f32>(0.7686, 0.498, 0.6275),
	vec3<f32>(0.8902, 0.5843, 0.5647),
	vec3<f32>(0.9569, 0.6784, 0.4863),
	vec3<f32>(0.9765, 0.7843, 0.4667),
	vec3<f32>(0.9922, 0.8784, 0.5569),
	vec3<f32>(1.0, 0.9529, 0.7686),
	vec3<f32>(0.0431, 0.051, 0.1216),
	vec3<f32>(0.0784, 0.0902, 0.2),
	vec3<f32>(0.1216, 0.1373, 0.3137),
	vec3<f32>(0.1882, 0.1882, 0.4314),
	vec3<f32>(0.2941, 0.2471, 0.5255),
	vec3<f32>(0.4588, 0.3216, 0.6039),
	vec3<f32>(0.6588, 0.4157, 0.6392),
	vec3<f32>(0.851, 0.5412, 0.651),
	vec3<f32>(0.949, 0.702, 0.6549),
	vec3<f32>(0.9843, 0.8627, 0.7529)
);

const N_XING: i32 = 4;
const K_XING: array<vec4<f32>, 4> = array<vec4<f32>, 4>(
	vec4<f32>(-1.25, 0.85, 1.0, 0.0),
	vec4<f32>(1.25, 0.85, 1.0, 0.0),
	vec4<f32>(-1.25, -1.85, -1.0, 0.0),
	vec4<f32>(1.25, -1.85, -1.0, 0.0)
);

const N_POLE: i32 = 2;
const K_POLE: array<vec4<f32>, 2> = array<vec4<f32>, 2>(
	vec4<f32>(-2.3, -1.62, 2.35, 0.2),
	vec4<f32>(2.75, -1.62, 2.35, 0.2)
);

const N_WIRE: i32 = 36;
const K_WIRE_A: array<vec3<f32>, 36> = array<vec3<f32>, 36>(
	vec3<f32>(-9.0, 1.52, -1.8),
	vec3<f32>(-6.7667, 1.3422, -1.8),
	vec3<f32>(-4.5333, 1.3422, -1.8),
	vec3<f32>(-2.3, 1.52, -1.8),
	vec3<f32>(-1.4583, 1.4422, -1.8),
	vec3<f32>(-0.6167, 1.3956, -1.8),
	vec3<f32>(0.225, 1.38, -1.8),
	vec3<f32>(1.0667, 1.3956, -1.8),
	vec3<f32>(1.9083, 1.4422, -1.8),
	vec3<f32>(2.75, 1.52, -1.8),
	vec3<f32>(4.8333, 1.3422, -1.8),
	vec3<f32>(6.9167, 1.3422, -1.8),
	vec3<f32>(-9.0, 1.52, -1.44),
	vec3<f32>(-6.7667, 1.2889, -1.44),
	vec3<f32>(-4.5333, 1.2889, -1.44),
	vec3<f32>(-2.3, 1.52, -1.44),
	vec3<f32>(-1.4583, 1.4089, -1.44),
	vec3<f32>(-0.6167, 1.3422, -1.44),
	vec3<f32>(0.225, 1.32, -1.44),
	vec3<f32>(1.0667, 1.3422, -1.44),
	vec3<f32>(1.9083, 1.4089, -1.44),
	vec3<f32>(2.75, 1.52, -1.44),
	vec3<f32>(4.8333, 1.2889, -1.44),
	vec3<f32>(6.9167, 1.2889, -1.44),
	vec3<f32>(-9.0, 1.22, -1.62),
	vec3<f32>(-6.7667, 0.9356, -1.62),
	vec3<f32>(-4.5333, 0.9356, -1.62),
	vec3<f32>(-2.3, 1.22, -1.62),
	vec3<f32>(-1.4583, 1.0756, -1.62),
	vec3<f32>(-0.6167, 0.9889, -1.62),
	vec3<f32>(0.225, 0.96, -1.62),
	vec3<f32>(1.0667, 0.9889, -1.62),
	vec3<f32>(1.9083, 1.0756, -1.62),
	vec3<f32>(2.75, 1.22, -1.62),
	vec3<f32>(4.8333, 0.9356, -1.62),
	vec3<f32>(6.9167, 0.9356, -1.62)
);
const K_WIRE_B: array<vec3<f32>, 36> = array<vec3<f32>, 36>(
	vec3<f32>(-6.7667, 1.3422, -1.8),
	vec3<f32>(-4.5333, 1.3422, -1.8),
	vec3<f32>(-2.3, 1.52, -1.8),
	vec3<f32>(-1.4583, 1.4422, -1.8),
	vec3<f32>(-0.6167, 1.3956, -1.8),
	vec3<f32>(0.225, 1.38, -1.8),
	vec3<f32>(1.0667, 1.3956, -1.8),
	vec3<f32>(1.9083, 1.4422, -1.8),
	vec3<f32>(2.75, 1.52, -1.8),
	vec3<f32>(4.8333, 1.3422, -1.8),
	vec3<f32>(6.9167, 1.3422, -1.8),
	vec3<f32>(9.0, 1.52, -1.8),
	vec3<f32>(-6.7667, 1.2889, -1.44),
	vec3<f32>(-4.5333, 1.2889, -1.44),
	vec3<f32>(-2.3, 1.52, -1.44),
	vec3<f32>(-1.4583, 1.4089, -1.44),
	vec3<f32>(-0.6167, 1.3422, -1.44),
	vec3<f32>(0.225, 1.32, -1.44),
	vec3<f32>(1.0667, 1.3422, -1.44),
	vec3<f32>(1.9083, 1.4089, -1.44),
	vec3<f32>(2.75, 1.52, -1.44),
	vec3<f32>(4.8333, 1.2889, -1.44),
	vec3<f32>(6.9167, 1.2889, -1.44),
	vec3<f32>(9.0, 1.52, -1.44),
	vec3<f32>(-6.7667, 0.9356, -1.62),
	vec3<f32>(-4.5333, 0.9356, -1.62),
	vec3<f32>(-2.3, 1.22, -1.62),
	vec3<f32>(-1.4583, 1.0756, -1.62),
	vec3<f32>(-0.6167, 0.9889, -1.62),
	vec3<f32>(0.225, 0.96, -1.62),
	vec3<f32>(1.0667, 0.9889, -1.62),
	vec3<f32>(1.9083, 1.0756, -1.62),
	vec3<f32>(2.75, 1.22, -1.62),
	vec3<f32>(4.8333, 0.9356, -1.62),
	vec3<f32>(6.9167, 0.9356, -1.62),
	vec3<f32>(9.0, 1.22, -1.62)
);

const N_LAMP: i32 = 6;
const K_LAMP: array<vec4<f32>, 6> = array<vec4<f32>, 6>(
	vec4<f32>(-1.3, 1.62, 1.5, 0.3),
	vec4<f32>(1.32, -2.3, 1.5, -0.3),
	vec4<f32>(-1.32, -5.2, 1.5, 0.3),
	vec4<f32>(1.32, -8.0, 1.5, -0.3),
	vec4<f32>(-1.32, -11.0, 1.5, 0.3),
	vec4<f32>(1.32, -14.0, 1.5, -0.3)
);

const K_VEND: vec2<f32> = vec2<f32>(1.76, 1.42);

const N_LIGHT: i32 = 7;
const K_LIGHT: array<vec4<f32>, 7> = array<vec4<f32>, 7>(
	vec4<f32>(-1.0, 0.7, 1.62, 1.0),
	vec4<f32>(1.02, 0.7, -2.3, 1.0),
	vec4<f32>(-1.02, 0.7, -5.2, 1.0),
	vec4<f32>(1.02, 0.7, -8.0, 1.0),
	vec4<f32>(-1.02, 0.7, -11.0, 1.0),
	vec4<f32>(1.02, 0.7, -14.0, 1.0),
	vec4<f32>(1.76, -0.33, 1.72, 0.45)
);

const N_TREE: i32 = 8;
const K_TREE_T: array<vec4<f32>, 8> = array<vec4<f32>, 8>(
	vec4<f32>(-1.98, 1.05, 0.95, 0.0),
	vec4<f32>(2.08, 0.75, 1.0, 0.0),
	vec4<f32>(-4.3, -3.4, 1.1, 0.0),
	vec4<f32>(-1.45, -3.7, 0.85, 1.0),
	vec4<f32>(1.5, -3.6, 0.9, 1.0),
	vec4<f32>(3.95, -3.5, 1.1, 0.0),
	vec4<f32>(-3.1, -5.6, 1.0, 0.0),
	vec4<f32>(5.6, -5.2, 1.1, 1.0)
);
const K_TREE_L: array<vec4<f32>, 8> = array<vec4<f32>, 8>(
	vec4<f32>(-2.06, 0.2, 1.05, 0.0),
	vec4<f32>(2.18, 0.25, 0.75, 0.0),
	vec4<f32>(-4.25, 0.35, -3.4, 0.0),
	vec4<f32>(-1.45, 0.1, -3.7, 0.0),
	vec4<f32>(1.54, 0.15, -3.6, 0.0),
	vec4<f32>(3.89, 0.35, -3.5, 0.0),
	vec4<f32>(-3.1, 0.25, -5.6, 0.0),
	vec4<f32>(5.6, 0.35, -5.2, 0.0)
);
const K_TREE_BR: array<vec4<f32>, 24> = array<vec4<f32>, 24>(
	vec4<f32>(-1.6236, 0.4479, 1.0089, 0.0),
	vec4<f32>(-2.193, 0.4566, 1.3209, 0.0),
	vec4<f32>(-2.3111, 0.6019, 0.7113, 0.0),
	vec4<f32>(2.6157, 0.8143, 0.6849, 0.0),
	vec4<f32>(2.0677, 0.5397, 0.9737, 0.0),
	vec4<f32>(1.9812, 0.7615, 0.4136, 0.0),
	vec4<f32>(-3.6011, 0.6585, -3.3314, 0.0),
	vec4<f32>(-4.359, 0.8973, -2.9592, 0.0),
	vec4<f32>(-4.4893, 1.0925, -3.8181, 0.0),
	vec4<f32>(-1.0627, 0.3306, -3.6726, 0.0),
	vec4<f32>(-1.5314, 0.4999, -3.5064, 0.0),
	vec4<f32>(-1.6888, 0.5402, -3.8949, 0.0),
	vec4<f32>(2.0045, 0.3541, -3.6299, 0.0),
	vec4<f32>(1.4204, 0.4546, -3.4235, 0.0),
	vec4<f32>(1.3725, 0.3177, -3.8711, 0.0),
	vec4<f32>(4.2291, 0.8971, -3.5194, 0.0),
	vec4<f32>(3.7088, 0.6556, -3.2452, 0.0),
	vec4<f32>(3.6724, 0.7537, -3.7968, 0.0),
	vec4<f32>(-2.7657, 0.493, -5.6055, 0.0),
	vec4<f32>(-3.202, 0.513, -5.2626, 0.0),
	vec4<f32>(-3.2125, 0.612, -5.8851, 0.0),
	vec4<f32>(6.1225, 1.0313, -5.2429, 0.0),
	vec4<f32>(5.4533, 0.5773, -4.8878, 0.0),
	vec4<f32>(5.4628, 1.0328, -5.6303, 0.0)
);
const K_BLOB: array<vec4<f32>, 48> = array<vec4<f32>, 48>(
	vec4<f32>(-1.6236, 0.5479, 1.0089, 0.4248),
	vec4<f32>(-1.9413, 0.7545, 1.2928, 0.4615),
	vec4<f32>(-2.193, 0.5566, 1.3209, 0.4732),
	vec4<f32>(-2.4695, 0.6195, 1.0631, 0.5404),
	vec4<f32>(-2.3111, 0.7019, 0.7113, 0.5611),
	vec4<f32>(-1.7198, 0.6511, 0.7539, 0.407),
	vec4<f32>(2.6157, 0.9143, 0.6849, 0.3971),
	vec4<f32>(2.5408, 0.7146, 1.0271, 0.4722),
	vec4<f32>(2.0677, 0.6397, 0.9737, 0.3882),
	vec4<f32>(1.8566, 0.8105, 0.7167, 0.4473),
	vec4<f32>(1.9812, 0.8615, 0.4136, 0.4266),
	vec4<f32>(2.3966, 0.9408, 0.4269, 0.4711),
	vec4<f32>(-3.6011, 0.7585, -3.3314, 0.4954),
	vec4<f32>(-3.9992, 0.9532, -3.1261, 0.5841),
	vec4<f32>(-4.359, 0.9973, -2.9592, 0.5673),
	vec4<f32>(-4.7561, 1.0085, -3.4983, 0.5003),
	vec4<f32>(-4.4893, 1.1925, -3.8181, 0.5272),
	vec4<f32>(-4.0335, 1.0648, -3.668, 0.5665),
	vec4<f32>(-1.0627, 0.4306, -3.6726, 0.4191),
	vec4<f32>(-1.311, 0.4926, -3.5347, 0.3783),
	vec4<f32>(-1.5314, 0.5999, -3.5064, 0.3088),
	vec4<f32>(-1.7557, 0.636, -3.6447, 0.3252),
	vec4<f32>(-1.6888, 0.6402, -3.8949, 0.3506),
	vec4<f32>(-1.2574, 0.4764, -3.8774, 0.4029),
	vec4<f32>(2.0045, 0.4541, -3.6299, 0.4344),
	vec4<f32>(1.7655, 0.5794, -3.4155, 0.3463),
	vec4<f32>(1.4204, 0.5546, -3.4235, 0.3505),
	vec4<f32>(1.1242, 0.6564, -3.5723, 0.3915),
	vec4<f32>(1.3725, 0.4177, -3.8711, 0.3984),
	vec4<f32>(1.8588, 0.6967, -3.8466, 0.4203),
	vec4<f32>(4.2291, 0.9971, -3.5194, 0.4918),
	vec4<f32>(4.1386, 0.7612, -3.2727, 0.4321),
	vec4<f32>(3.7088, 0.7556, -3.2452, 0.4295),
	vec4<f32>(3.5078, 1.1172, -3.4324, 0.4854),
	vec4<f32>(3.6724, 0.8537, -3.7968, 0.4467),
	vec4<f32>(4.0945, 1.1766, -3.9066, 0.4421),
	vec4<f32>(-2.7657, 0.593, -5.6055, 0.4564),
	vec4<f32>(-2.8094, 0.6196, -5.273, 0.4209),
	vec4<f32>(-3.202, 0.613, -5.2626, 0.5321),
	vec4<f32>(-3.5337, 0.9873, -5.609, 0.3824),
	vec4<f32>(-3.2125, 0.712, -5.8851, 0.4908),
	vec4<f32>(-2.9617, 0.8976, -5.9298, 0.5031),
	vec4<f32>(6.1225, 1.1313, -5.2429, 0.4371),
	vec4<f32>(5.7618, 1.0149, -4.7989, 0.5368),
	vec4<f32>(5.4533, 0.6773, -4.8878, 0.4875),
	vec4<f32>(5.2217, 0.9924, -5.1119, 0.4468),
	vec4<f32>(5.4628, 1.1328, -5.6303, 0.4755),
	vec4<f32>(5.8751, 0.7713, -5.4153, 0.4614)
);
const K_TREE_B: array<vec4<f32>, 8> = array<vec4<f32>, 8>(
	vec4<f32>(-2.108, 0.7225, 1.05, 1.435),
	vec4<f32>(2.24, 0.745, 0.75, 1.37),
	vec4<f32>(-4.22, 0.9275, -3.4, 1.565),
	vec4<f32>(-1.45, 0.485, -3.7, 1.11),
	vec4<f32>(1.564, 0.5625, -3.6, 1.175),
	vec4<f32>(3.854, 0.9, -3.5, 1.5),
	vec4<f32>(-3.1, 0.745, -5.6, 1.37),
	vec4<f32>(5.6, 0.8725, -5.2, 1.435)
);

const N_BUSH: i32 = 12;
const K_BUSH: array<vec4<f32>, 12> = array<vec4<f32>, 12>(
	vec4<f32>(-2.4, -0.6285, 0.52, 0.27),
	vec4<f32>(-1.82, -0.66, 0.5, 0.2),
	vec4<f32>(1.8, -0.651, 0.5, 0.22),
	vec4<f32>(2.55, -0.624, 0.47, 0.28),
	vec4<f32>(-1.9, -0.642, -1.78, 0.24),
	vec4<f32>(-2.65, -0.615, -1.82, 0.3),
	vec4<f32>(1.9, -0.633, -1.8, 0.26),
	vec4<f32>(2.9, -0.615, -1.78, 0.3),
	vec4<f32>(-3.5, -0.615, -1.9, 0.3),
	vec4<f32>(3.6, -0.633, -1.9, 0.26),
	vec4<f32>(-3.3, -0.615, 0.6, 0.3),
	vec4<f32>(3.3, -0.615, 0.55, 0.3)
);

const N_HOUSE: i32 = 10;
const K_HOUSE_C: array<vec4<f32>, 10> = array<vec4<f32>, 10>(
	vec4<f32>(-2.75, -4.3, 0.95, 0.6),
	vec4<f32>(2.7, -4.4, 0.85, 0.6),
	vec4<f32>(-6.0, -7.2, 1.4, 0.7),
	vec4<f32>(4.9, -7.6, 1.5, 0.7),
	vec4<f32>(-2.7, -7.3, 0.95, 0.9),
	vec4<f32>(2.75, -7.9, 0.95, 1.0),
	vec4<f32>(-2.9, -10.8, 1.05, 1.2),
	vec4<f32>(2.95, -11.4, 1.05, 1.2),
	vec4<f32>(-3.1, -15.0, 1.15, 1.6),
	vec4<f32>(3.1, -15.6, 1.15, 1.6)
);
const K_HOUSE_H: array<vec4<f32>, 10> = array<vec4<f32>, 10>(
	vec4<f32>(0.95, 0.42, 8.0, 0.0),
	vec4<f32>(1.35, 0.4, 8.0, 0.0),
	vec4<f32>(2.5, 0.0, 20.0, 0.0),
	vec4<f32>(3.0, 0.0, 20.0, 0.0),
	vec4<f32>(1.9, 0.0, 20.0, 0.0),
	vec4<f32>(2.5, 0.0, 8.0, 0.0),
	vec4<f32>(3.2, 0.0, 20.0, 0.0),
	vec4<f32>(2.4, 0.0, 20.0, 0.0),
	vec4<f32>(3.9, 0.0, 20.0, 0.0),
	vec4<f32>(3.3, 0.0, 8.0, 0.0)
);

const N_WHO: i32 = 6;
const N_KEY: i32 = 9;
const K_WHO: array<vec4<f32>, 6> = array<vec4<f32>, 6>(
	vec4<f32>(0.0, 1.0, 38.0, 0.0),
	vec4<f32>(2.0, 0.62, 38.0, 0.0),
	vec4<f32>(0.0, 0.95, 40.0, 0.0),
	vec4<f32>(4.0, 1.0, 43.0, 0.0),
	vec4<f32>(3.0, 1.02, 41.0, 0.0),
	vec4<f32>(1.0, 0.9, 38.0, 0.0)
);
const K_PATH: array<vec4<f32>, 54> = array<vec4<f32>, 54>(
	vec4<f32>(0.0, -0.5, 1.55, -1.5708),
	vec4<f32>(15.4, -0.5, 1.55, -1.5708),
	vec4<f32>(23.4, -0.5, -2.7, -1.5708),
	vec4<f32>(32.6, -5.2, -2.7, -1.5708),
	vec4<f32>(32.7, -3.3, 2.1, -1.5708),
	vec4<f32>(37.3, -0.5, 2.1, -1.5708),
	vec4<f32>(38.3, -0.5, 1.55, -1.5708),
	vec4<f32>(38.3, -0.5, 1.55, -1.5708),
	vec4<f32>(44.0, -0.5, 1.55, -1.5708),
	vec4<f32>(0.0, -0.23, 1.65, -1.5708),
	vec4<f32>(15.65, -0.23, 1.65, -1.5708),
	vec4<f32>(23.65, -0.23, -2.6, -1.5708),
	vec4<f32>(32.85, -4.93, -2.6, -1.5708),
	vec4<f32>(32.95, -3.03, 2.2, -1.5708),
	vec4<f32>(37.55, -0.23, 2.2, -1.5708),
	vec4<f32>(38.55, -0.23, 1.65, -1.5708),
	vec4<f32>(38.55, -0.23, 1.65, -1.5708),
	vec4<f32>(44.0, -0.23, 1.65, -1.5708),
	vec4<f32>(0.0, 0.45, 1.72, -1.5708),
	vec4<f32>(15.7, 0.45, 1.72, -1.5708),
	vec4<f32>(23.9, 0.5, -2.72, -1.5708),
	vec4<f32>(33.0, 5.3, -2.72, -1.5708),
	vec4<f32>(33.1, 3.4, 2.25, -1.5708),
	vec4<f32>(38.3, 0.45, 2.25, -1.5708),
	vec4<f32>(39.1, 0.45, 1.72, -1.5708),
	vec4<f32>(39.1, 0.45, 1.72, -1.5708),
	vec4<f32>(44.0, 0.45, 1.72, -1.5708),
	vec4<f32>(0.0, 0.75, 1.6, -1.5708),
	vec4<f32>(15.8, 0.75, 1.6, -1.5708),
	vec4<f32>(24.0, 0.8, -2.84, -1.5708),
	vec4<f32>(33.1, 5.6, -2.84, -1.5708),
	vec4<f32>(33.2, 3.7, 2.13, -1.5708),
	vec4<f32>(38.4, 0.75, 2.13, -1.5708),
	vec4<f32>(39.2, 0.75, 1.6, -1.5708),
	vec4<f32>(39.2, 0.75, 1.6, -1.5708),
	vec4<f32>(44.0, 0.75, 1.6, -1.5708),
	vec4<f32>(0.0, 0.35, -2.35, 1.5708),
	vec4<f32>(15.5, 0.35, -2.35, 1.5708),
	vec4<f32>(23.5, 0.35, 2.2, 1.5708),
	vec4<f32>(28.8, 3.5, 2.25, 1.5708),
	vec4<f32>(28.9, -5.3, -2.72, 1.5708),
	vec4<f32>(33.0, -5.3, -2.72, 1.5708),
	vec4<f32>(42.5, 0.35, -2.72, 1.5708),
	vec4<f32>(43.2, 0.35, -2.35, 1.5708),
	vec4<f32>(44.0, 0.35, -2.35, 1.5708),
	vec4<f32>(0.0, -0.35, -2.5, 1.5708),
	vec4<f32>(15.9, -0.35, -2.5, 1.5708),
	vec4<f32>(24.0, -0.35, 2.15, 1.5708),
	vec4<f32>(29.4, -3.5, 2.2, 1.5708),
	vec4<f32>(29.5, 5.3, -2.78, 1.5708),
	vec4<f32>(32.0, 5.3, -2.78, 1.5708),
	vec4<f32>(41.6, -0.35, -2.78, 1.5708),
	vec4<f32>(42.2, -0.35, -2.5, 1.5708),
	vec4<f32>(44.0, -0.35, -2.5, 1.5708)
);


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
]==]

M.SHOW = [==[
fn layer(input: LayerInput) -> vec4<f32> {
	let sz = zgx_scene_size();
	let uv = (floor(input.p / max(input.size, vec2<f32>(1.0)) * sz) + 0.5) / sz;
	let c = zgx_scene(uv);
	let pb = input.params[1];
	// Muted: every colour drawn a share of the way toward the evening sky's.
	let quiet = mix(c.rgb, vec3<f32>(0.07, 0.08, 0.19), input.params[2].y);
	return vec4<f32>(quiet * pb.y, c.a * pb.x);
}
]==]

return M

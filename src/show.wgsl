fn layer(input: LayerInput) -> vec4<f32> {
	let sz = zgx_scene_size();
	let uv = (floor(input.p / max(input.size, vec2<f32>(1.0)) * sz) + 0.5) / sz;
	let c = zgx_scene(uv);
	let pb = input.params[1];
	// Muted: every colour drawn a share of the way toward the evening sky's.
	let quiet = mix(c.rgb, vec3<f32>(0.07, 0.08, 0.19), input.params[2].y);
	return vec4<f32>(quiet * pb.y, c.a * pb.x);
}

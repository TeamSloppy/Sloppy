import AdaEngine

struct SloppyEdgeGlowMaterial: UIShaderMaterial {
    static func fragmentShader() throws -> AssetHandle<ShaderSource> {
        let source = """
        #version 450 core
        #pragma stage : frag

        #include <AdaEngine/UIShaderMaterial.frag>

        float glowBand(float value, float inner, float outer)
        {
            return 1.0 - smoothstep(inner, outer, value);
        }

        [[main]]
        void sloppy_edge_glow_fragment()
        {
            vec2 uv = Input.UV;
            vec2 edgeDistance = min(uv, 1.0 - uv);
            float edge = min(edgeDistance.x, edgeDistance.y);

            float sideGlow = glowBand(edge, 0.018, 0.22);
            float softBloom = glowBand(edge, 0.0, 0.42) * 0.32;

            float top = glowBand(uv.y, 0.02, 0.28);
            float right = glowBand(1.0 - uv.x, 0.02, 0.24);
            float bottom = glowBand(1.0 - uv.y, 0.02, 0.22);
            float left = glowBand(uv.x, 0.02, 0.20);

            vec3 cyan = vec3(0.00, 0.94, 1.00);
            vec3 pink = vec3(1.00, 0.18, 0.44);
            vec3 violet = vec3(0.72, 0.38, 1.00);

            vec3 color = cyan * (top + left * 0.55)
                + pink * (right * 1.05 + bottom * 0.64)
                + violet * (top * right + left * bottom) * 0.7;

            float alpha = clamp(sideGlow * 0.34 + softBloom, 0.0, 0.54);
            COLOR = vec4(color * (0.62 + sideGlow * 0.48), alpha);

            if (COLOR.a <= 0.001) {
                discard;
            }
        }
        """

        return AssetHandle(try ShaderSource(source: source))
    }
}

@MainActor
enum SloppyShaderEffects {
    static let edgeGlow = CustomMaterial(SloppyEdgeGlowMaterial())
}


import AdaEngine

struct SloppyEdgeGlowMaterial: UIShaderMaterial {
    static func vertexShader() throws -> AssetHandle<ShaderSource> {
        let source = """
        #version 450 core
        #pragma stage : vert

        #include <AdaEngine/View.glsl>

        layout (location = 0) in vec4 a_Position;
        layout (location = 1) in vec4 a_Color;
        layout (location = 2) in vec2 a_TexCoordinate;

        layout (location = 0) out vec4 Output_Color;
        layout (location = 1) out vec2 Output_UV;

        [[main]]
        void sloppy_edge_glow_vertex()
        {
            Output_Color = a_Color;
            Output_UV = a_TexCoordinate;
            gl_Position = u_ViewProjection * a_Position;
        }
        """

        return AssetHandle(try ShaderSource(source: source))
    }

    static func fragmentShader() throws -> AssetHandle<ShaderSource> {
        let source = """
        #version 450 core
        #pragma stage : frag

        layout (location = 0) in vec4 Input_Color;
        layout (location = 1) in vec2 Input_UV;
        layout (location = 0) out vec4 COLOR;

        float glowBand(float value, float inner, float outer)
        {
            return 1.0 - smoothstep(inner, outer, value);
        }

        [[main]]
        void sloppy_edge_glow_fragment()
        {
            vec2 uv = Input_UV;
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
            COLOR = vec4(color * (0.62 + sideGlow * 0.48) * Input_Color.rgb, alpha * Input_Color.a);

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

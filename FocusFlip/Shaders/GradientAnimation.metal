#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position;
};

struct VertexOut {
    float4 position [[position]];
    float time;
    float2 viewSize;
    int page;
};

// Custom colors structure (5 colors, each with RGB)
struct CustomColors {
    float3 color1;
    float3 color2;
    float3 color3;
    float3 color4;
    float3 color5;
};

/// Passthrough vertex shader
vertex VertexOut gradient_animation_vertex(const device packed_float3* in [[ buffer(0) ]],
                                           constant float &time [[buffer(1)]],
                                           const device packed_float2* viewSize [[buffer(2)]],
                                           constant int &page [[buffer(3)]],
                                           unsigned int vid [[ vertex_id ]]) {
    VertexOut out;
    out.position = float4(in[vid], 1);
    out.time = time + (float)page * 10.;
    out.viewSize = float2(viewSize->x, viewSize->y);
    out.page = page;
    return out;
}

float noise1(float seed1, float seed2){
    return(
           fract(seed1+12.34567*
                 fract(100.*(abs(seed1*0.91)+seed2+94.68)*
                       fract((abs(seed2*0.41)+45.46)*
                             fract((abs(seed2)+757.21)*
                                   fract(seed1*0.0171))))))
    * 1.0038 - 0.00185;
}

float noise2(float seed1, float seed2, float seed3){
    float buff1 = abs(seed1+100.81) + 1000.3;
    float buff2 = abs(seed2+100.45) + 1000.2;
    float buff3 = abs(noise1(seed1, seed2)+seed3) + 1000.1;
    buff1 = (buff3*fract(buff2*fract(buff1*fract(buff2*0.146))));
    buff2 = (buff2*fract(buff2*fract(buff1+buff2*fract(buff3*0.52))));
    buff1 = noise1(buff1, buff2);
    return(buff1);
}

float noise3(float seed1, float seed2, float seed3) {
    float buff1 = abs(seed1+100.813) + 1000.314;
    float buff2 = abs(seed2+100.453) + 1000.213;
    float buff3 = abs(noise1(buff2, buff1)+seed3) + 1000.17;
    buff1 = (buff3*fract(buff2*fract(buff1*fract(buff2*0.14619))));
    buff2 = (buff2*fract(buff2*fract(buff1+buff2*fract(buff3*0.5215))));
    buff1 = noise2(noise1(seed2,buff1), noise1(seed1,buff2), noise1(seed3,buff3));
    return(buff1);
}

/// Fragment shader for gradient animation
fragment float4 gradient_animation_fragment(VertexOut in [[stage_in]],
                                           constant CustomColors* customColors [[buffer(3)]],
                                           constant int &useCustomColors [[buffer(4)]],
                                           constant float3 &backgroundColor [[buffer(5)]]) {
    float2 st = in.position.xy/in.viewSize.xy;
    st = float2(tan(st.x), sin(st.y));

    st.x += (sin(in.time/2.1)+2.0)*0.12*sin(sin(st.y*st.x+in.time/6.0)*8.2);
    st.y -= (cos(in.time/1.73)+2.0)*0.12*cos(st.x*st.y*5.1-in.time/4.0);

    float3 bg = backgroundColor;

    float3 color1;
    float3 color2;
    float3 color3;
    float3 color4;
    float3 color5;

    // Use custom colors if provided, otherwise use preset pages
    if (useCustomColors != 0) {
        color1 = customColors->color1;
        color2 = customColors->color2;
        color3 = customColors->color3;
        color4 = customColors->color4;
        color5 = customColors->color5;
    } else if (in.page == 0) {
        color1 = float3(252.0/255.0, 60.0/255.0, 0.0/255.0);
        color2 = float3(253.0/255.0, 0.0/255.0, 12.0/255.0);
        color3 = float3(26.0/255.0, 0.5/255.0, 6.0/255.0);
        color4 = float3(128.0/255.0, 0.0/255.0, 17.0/255.0);
        color5 = float3(255.0/255.0, 15.0/255.0, 8.0/255.0);
    } else if (in.page == 1) {
        color1 = float3(183.0/255.0, 246.0/255.0, 254.0/255.0);
        color2 = float3(50.0/255.0, 160.0/255.0, 251.0/255.0);
        color3 = float3(3.0/255.0, 79.0/255.0, 231.0/255.0);
        color4 = float3(1.0/255.0, 49.0/255.0, 161.0/255.0);
        color5 = float3(3.0/255.0, 12.0/255.0, 47.0/255.0);
    } else if (in.page == 2) {
        color1 = float3(102.0/255.0, 231.0/255.0, 255.0/255.0);
        color2 = float3(4.0/255.0, 207.0/255.0, 213.0/255.0);
        color3 = float3(0.0/255.0, 160.0/255.0, 119.0/255.0);
        color4 = float3(0.0/255.0, 175.0/255.0, 139.0/255.0);
        color5 = float3(2.0/255.0, 37.0/255.0, 27.0/255.0);
    } else {
        color1 = float3(255.0/255.0, 50.0/255.0, 134.0/255.0);
        color2 = float3(236.0/255.0, 18.0/255.0, 60.0/255.0);
        color3 = float3(178.0/255.0, 254.0/255.0, 0.0/255.0);
        color4 = float3(0.0/255.0, 248.0/255.0, 209.0/255.0);
        color5 = float3(0.0/255.0, 186.0/255.0, 255.0/255.0);
    }

    float mixValue = smoothstep(0.0, 0.8, distance(st,float2(sin(in.time/5.0)+0.5,sin(in.time/6.1)+0.5)));
    float3 outColor = mix(color1,bg,mixValue);

    mixValue = smoothstep(0.1, 0.9, distance(st,float2(sin(in.time/3.94)+0.7,sin(in.time/4.2)-0.1)));
    outColor = mix(color2,outColor,mixValue);

    mixValue = smoothstep(0.1, 0.8, distance(st,float2(sin(in.time/3.43)+0.2,sin(in.time/3.2)+0.45)));
    outColor = mix(color3,outColor,mixValue);

    mixValue = smoothstep(0.14, 0.89, distance(st,float2(sin(in.time/5.4)-0.3,sin(in.time/5.7)+0.7)));
    outColor = mix(color4,outColor,mixValue);

    mixValue = smoothstep(0.01, 0.89, distance(st,float2(sin(in.time/9.5)+0.23,sin(in.time/3.95)+0.23)));
    outColor = mix(color5,outColor,mixValue);

    /// ----

    mixValue = smoothstep(0.01, 0.89, distance(st,float2(cos(in.time/8.5)/2.+0.13,sin(in.time/4.95)-0.23)));
    outColor = mix(color1,outColor,mixValue);

    mixValue = smoothstep(0.1, 0.9, distance(st,float2(cos(in.time/6.94)/2.+0.7,sin(in.time/4.112)+0.66)));
    outColor = mix(color2,outColor,mixValue);

    mixValue = smoothstep(0.1, 0.8, distance(st,float2(cos(in.time/4.43)/2.+0.2,sin(in.time/6.2)+0.85)));
    outColor = mix(color3,outColor,mixValue);

    mixValue = smoothstep(0.14, 0.89, distance(st,float2(cos(in.time/10.4)/2.-0.3,sin(in.time/5.7)+0.8)));
    outColor = mix(color4,outColor,mixValue);

    mixValue = smoothstep(0.01, 0.89, distance(st,float2(cos(in.time/4.5)/2.+0.63,sin(in.time/4.95)+0.93)));
    outColor = mix(color5,outColor,mixValue);

    float2 st_unwarped = in.position.xy/in.viewSize.xy;
    float3 noise = float3(noise3(st_unwarped.x*0.000001, st_unwarped.y*0.000001, in.time * 1e-15));
    outColor = (outColor * 0.85) - (noise * 0.1);

    return float4(outColor, 1.0);
}

import { useEffect, useRef } from "react";

const TARGET_FPS = 24;
const FRAME_INTERVAL = 1000 / TARGET_FPS;
const MAX_CANVAS_PIXELS = 720_000;
const MAX_DPR = 1;

export function WebGLBackground() {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    // Standard webgl setup, disable alpha/depth for better background performance
    const gl = canvas.getContext("webgl", { alpha: false, depth: false, antialias: false });
    if (!gl) {
      console.warn("WebGL not supported");
      return;
    }

    const vsSource = `
      attribute vec2 a_position;
      void main() {
        gl_Position = vec4(a_position, 0.0, 1.0);
      }
    `;

    const fsSource = `
      precision highp float;
      uniform vec2 u_resolution;
      uniform float u_time;

      // Ashima 2D Simplex Noise
      vec3 permute(vec3 x) { return mod(((x*34.0)+1.0)*x, 289.0); }
      float snoise(vec2 v){
        const vec4 C = vec4(0.211324865405187, 0.366025403784439, -0.577350269189626, 0.024390243902439);
        vec2 i  = floor(v + dot(v, C.yy) );
        vec2 x0 = v -   i + dot(i, C.xx);
        vec2 i1;
        i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
        vec4 x12 = x0.xyxy + C.xxzz;
        x12.xy -= i1;
        i = mod(i, 289.0);
        vec3 p = permute( permute( i.y + vec3(0.0, i1.y, 1.0 )) + i.x + vec3(0.0, i1.x, 1.0 ));
        vec3 m = max(0.5 - vec3(dot(x0,x0), dot(x12.xy,x12.xy), dot(x12.zw,x12.zw)), 0.0);
        m = m*m ;
        m = m*m ;
        vec3 x = 2.0 * fract(p * C.www) - 1.0;
        vec3 h = abs(x) - 0.5;
        vec3 ox = floor(x + 0.5);
        vec3 a0 = x - ox;
        m *= 1.79284291400159 - 0.85373472095314 * ( a0*a0 + h*h );
        vec3 g;
        g.x  = a0.x  * x0.x  + h.x  * x0.y;
        g.yz = a0.yz * x12.xz + h.yz * x12.yw;
        return 130.0 * dot(m, g);
      }

      void main() {
        vec2 uv = gl_FragCoord.xy / u_resolution.xy;
        float aspect = u_resolution.x / u_resolution.y;
        
        vec2 p = uv;
        p.x *= aspect;

        // Clean, smooth animation timeline
        float t = u_time * 0.45; 

        // Two domain-warping noise passes keep the liquid acrylic feel without
        // making every pixel run a large stack of simplex samples.
        float n1 = snoise(p * 1.5 + vec2(t * 0.3, t * -0.2));
        float n2 = snoise(p * 2.0 + vec2(t * -0.2, t * 0.4));
        vec2 q = p + vec2(n1, n2) * 0.2;

        // Two color fields, then derive a third airy highlight from their motion.
        float f1 = snoise(q * 1.8 - vec2(t * 0.5, t * 0.2));
        float f2 = snoise(q * 1.6 + vec2(t * 0.4, t * 0.5));
        float f3 = sin((q.x * 2.7 - q.y * 1.8) + t * 1.25 + n1 * 1.4) * 0.5 + 0.5;
        
        float w1 = smoothstep(-0.3, 0.8, f1);
        float w2 = smoothstep(-0.4, 0.7, f2);
        float w3 = smoothstep(0.18, 0.92, f3);

        // Color palette featuring the custom light cyan-teal as requested
        vec3 colorBlue = vec3(0.35, 0.65, 1.0);   
        vec3 colorCyanTeal = vec3(0.55, 0.88, 0.84); 
        vec3 colorMint = vec3(0.40, 0.85, 0.75);  
        vec3 colorWhite = vec3(1.0, 1.0, 1.0);

        // Mix the color fields together cleanly
        vec3 color = colorWhite;
        color = mix(color, colorBlue, w1 * 0.6);
        color = mix(color, colorCyanTeal, w2 * 0.6);
        color = mix(color, colorMint, w3 * 0.5);

        // Diffuse into an airy, elegant aesthetic
        color = mix(colorWhite, color, 0.45);

        // Dynamic drifting white overlay for continuous color exchange.
        float clearWhite = smoothstep(0.15, 0.95, 0.5 + 0.5 * sin(q.x * 2.2 + q.y * 2.4 - t * 0.8 + n2));
        color = mix(color, colorWhite, clearWhite * 0.65);

        // Ambient lighting glow in center-ish region
        vec2 center = vec2(0.5 * aspect, 0.5);
        float dist = length(p - center);
        color += smoothstep(0.8, 0.0, dist) * 0.08;

        // EXACT background color of Demystify AI / Features section (zinc-50 = rgb(250, 250, 250))
        vec3 colorZinc50 = vec3(250.0 / 255.0, 250.0 / 255.0, 250.0 / 255.0);

        // Simple straight linear gradient at the bottom transition region
        // Fade smoothly from fluid background into the static zinc-50 color of Demystify AI section
        float bottomWeight = smoothstep(0.0, 0.35, uv.y);
        vec3 finalColor = mix(colorZinc50, color, bottomWeight);

        // Sophisticated architectural micro-grain
        float grain = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453);
        finalColor += (grain - 0.5) * 0.012 * bottomWeight;

        gl_FragColor = vec4(finalColor, 1.0);
      }
    `;

    const compileShader = (source: string, type: number) => {
      const shader = gl.createShader(type)!;
      gl.shaderSource(shader, source);
      gl.compileShader(shader);
      if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
        console.error("Shader error:", gl.getShaderInfoLog(shader));
        gl.deleteShader(shader);
        return null;
      }
      return shader;
    };

    const vs = compileShader(vsSource, gl.VERTEX_SHADER);
    const fs = compileShader(fsSource, gl.FRAGMENT_SHADER);
    if (!vs || !fs) return;

    const program = gl.createProgram()!;
    gl.attachShader(program, vs);
    gl.attachShader(program, fs);
    gl.linkProgram(program);
    gl.useProgram(program);

    const positionBuffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer);
    gl.bufferData(
      gl.ARRAY_BUFFER,
      new Float32Array([
        -1, -1,
         1, -1,
        -1,  1,
        -1,  1,
         1, -1,
         1,  1
      ]),
      gl.STATIC_DRAW
    );

    const positionLocation = gl.getAttribLocation(program, "a_position");
    gl.enableVertexAttribArray(positionLocation);
    gl.vertexAttribPointer(positionLocation, 2, gl.FLOAT, false, 0, 0);

    const timeLocation = gl.getUniformLocation(program, "u_time");
    const resolutionLocation = gl.getUniformLocation(program, "u_resolution");

    let animationFrameId = 0;
    let lastFrameTime = 0;
    const startTime = performance.now();
    let isCanvasVisible = true;
    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    const resize = () => {
      const rect = canvas.getBoundingClientRect();
      const width = rect.width;
      const height = rect.height;

      const baseDpr = reduceMotion ? 0.75 : Math.min(window.devicePixelRatio || 1, MAX_DPR);
      const pixelBudgetScale = Math.min(1, Math.sqrt(MAX_CANVAS_PIXELS / Math.max(width * height * baseDpr * baseDpr, 1)));
      const dpr = Math.max(0.65, baseDpr * pixelBudgetScale);
      const displayWidth = Math.max(1, Math.round(width * dpr));
      const displayHeight = Math.max(1, Math.round(height * dpr));

      if (canvas.width !== displayWidth || canvas.height !== displayHeight) {
        canvas.width = displayWidth;
        canvas.height = displayHeight;
        gl.viewport(0, 0, canvas.width, canvas.height);
      }
    };

    resize();

    const render = (time: number) => {
      if (!isCanvasVisible || document.hidden) {
        animationFrameId = 0;
        return;
      }

      if (time - lastFrameTime < FRAME_INTERVAL) {
        animationFrameId = requestAnimationFrame(render);
        return;
      }

      lastFrameTime = time;

      const elapsedSeconds = (time - startTime) * 0.001;
      
      gl.useProgram(program);
      gl.uniform1f(timeLocation, elapsedSeconds);
      gl.uniform2f(resolutionLocation, canvas.width, canvas.height);

      gl.drawArrays(gl.TRIANGLES, 0, 6);
      
      animationFrameId = requestAnimationFrame(render);
    };

    const startRenderLoop = () => {
      if (!animationFrameId && isCanvasVisible && !document.hidden) {
        animationFrameId = requestAnimationFrame(render);
      }
    };

    startRenderLoop();

    const resizeObserver = new ResizeObserver(resize);
    resizeObserver.observe(canvas);

    const intersectionObserver = new IntersectionObserver(
      ([entry]) => {
        isCanvasVisible = entry.isIntersecting;
        if (isCanvasVisible) {
          lastFrameTime = 0;
          startRenderLoop();
        } else if (animationFrameId) {
          cancelAnimationFrame(animationFrameId);
          animationFrameId = 0;
        }
      },
      { threshold: 0.01 }
    );
    intersectionObserver.observe(canvas);

    const handleVisibilityChange = () => {
      if (!document.hidden) {
        lastFrameTime = 0;
        startRenderLoop();
      } else if (animationFrameId) {
        cancelAnimationFrame(animationFrameId);
        animationFrameId = 0;
      }
    };

    document.addEventListener("visibilitychange", handleVisibilityChange);

    return () => {
      cancelAnimationFrame(animationFrameId);
      resizeObserver.disconnect();
      intersectionObserver.disconnect();
      document.removeEventListener("visibilitychange", handleVisibilityChange);
      gl.deleteBuffer(positionBuffer);
      gl.deleteProgram(program);
      gl.deleteShader(vs);
      gl.deleteShader(fs);
    };
  }, []);

  return (
    <div className="absolute inset-0 w-full h-full overflow-hidden bg-white">
      <canvas
        ref={canvasRef}
        className="block w-full h-full"
        style={{ pointerEvents: 'none' }}
      />
    </div>
  );
}


import numpy as np, onnxruntime as ort, matplotlib.pyplot as plt, math

# =========================================================
# Session
# =========================================================
def load_session(path="imit_nav_fast.onnx"):
    prov = ort.get_available_providers()
    if "CUDAExecutionProvider" in prov:
        print("Using GPU")
        return ort.InferenceSession(path, providers=["CUDAExecutionProvider"])
    print("Using CPU")
    return ort.InferenceSession(path, providers=["CPUExecutionProvider"])

def run_inference(sess, rays_lmr):
    x = np.asarray(rays_lmr, np.float32).reshape(1, 3)
    y = sess.run(None, {sess.get_inputs()[0].name: x})[0][0]
    return float(y[0]), float(y[1])  # steer, throttle


# =========================================================
# Track (sinusoidal corridor)
# =========================================================
def make_track():
    ys = np.linspace(0.0, 60.0, 600)
    xs = 3.0 * np.sin(0.15 * ys)
    W = 8.0
    left = np.column_stack((xs - W/2, ys))
    right = np.column_stack((xs + W/2, ys))
    return left, right, W


# =========================================================
# Geometry helpers
# =========================================================
def cross(ax, ay, bx, by): return ax*by - ay*bx
def dot(ax, ay, bx, by):   return ax*bx + ay*by
def norm(ax, ay):
    n = math.hypot(ax, ay)
    return (ax/n, ay/n) if n > 1e-12 else (0.0, 0.0)

# Ray (P + u*r, u>=0) vs segment (A + t*s, t in [0,1])
def ray_segment_intersection(Px, Py, rx, ry, Ax, Ay, Bx, By):
    sx, sy = (Bx - Ax), (By - Ay)
    den = cross(rx, ry, sx, sy)
    if abs(den) < 1e-12:
        return None  # parallel or collinear — treat as no hit
    qx, qy = Ax - Px, Ay - Py
    u = cross(qx, qy, sx, sy) / den
    t = cross(qx, qy, rx, ry) / den
    if u >= 0.0 and 0.0 <= t <= 1.0:
        # distance along ray is u, hit point:
        hx, hy = Px + u*rx, Py + u*ry
        return u, hx, hy, sx, sy
    return None

# Segment vs segment: move P->P2 against wall segment A->B
def move_segment_hit(Px, Py, P2x, P2y, Ax, Ay, Bx, By):
    rx, ry = (P2x - Px), (P2y - Py)
    sx, sy = (Bx - Ax), (By - Ay)
    den = cross(rx, ry, sx, sy)
    if abs(den) < 1e-12:
        return None
    qx, qy = Ax - Px, Ay - Py
    t = cross(qx, qy, sx, sy) / den   # along move [0..1]
    u = cross(qx, qy, rx, ry) / den   # along wall [0..1]
    if 0.0 <= t <= 1.0 and 0.0 <= u <= 1.0:
        hx, hy = Px + t*rx, Py + t*ry
        return t, hx, hy, sx, sy
    return None


def cast_rays(x, y, heading, left_wall, right_wall, max_range=10.0):
    fov = math.radians(90.0)
    # +45°, 0°, -45°  => [Left, Mid, Right]
    angs = ( +fov/2, 0.0, -fov/2 )
    out = []

    for a in angs:
        rx, ry = math.cos(heading + a), math.sin(heading + a)
        best_u = max_range
        # test both walls
        for wall in (left_wall, right_wall):
            for (x1, y1), (x2, y2) in zip(wall[:-1], wall[1:]):
                hit = ray_segment_intersection(x, y, rx, ry, x1, y1, x2, y2)
                if hit is None:
                    continue
                u, _, _, _, _ = hit
                if 0.0 <= u < best_u:
                    best_u = u
        out.append(min(best_u, max_range) / max_range)

    return out  # [L, M, R]


def step_with_collision(x, y, heading, steer, throttle, left, right, dt=0.15):
    max_turn = math.radians(35.0)
    speed = 3.0 * max(0.0, min(1.0, throttle))
    heading += steer * max_turn * dt
    vx, vy = math.cos(heading) * speed, math.sin(heading) * speed
    nx, ny = x + vx*dt, y + vy*dt

    first = None
    which = None
    for tag, wall in (("L", left), ("R", right)):
        for (x1, y1), (x2, y2) in zip(wall[:-1], wall[1:]):
            hit = move_segment_hit(x, y, nx, ny, x1, y1, x2, y2)
            if hit is None:
                continue
            t, hx, hy, sx, sy = hit
            if first is None or t < first[0]:
                first = (t, hx, hy, sx, sy)
                which = tag

    if first is None:
        return nx, ny, heading

    t, hx, hy, sx, sy = first
    if which == "L":
        nin_x, nin_y = norm(sy, -sx)
    else:  # "R"
        nin_x, nin_y = norm(-sy, sx)

    vnx = vx; vny = vy
    vn = dot(vnx, vny, nin_x, nin_y)
    vtx, vty = vnx - vn*nin_x, vny - vn*nin_y
    EPS = 1e-3
    rx, ry = hx + nin_x*EPS, hy + nin_y*EPS

    remain = (1.0 - t) * dt
    rx += vtx * remain
    ry += vty * remain

    if abs(vtx) + abs(vty) > 1e-9:
        heading = math.atan2(vty, vtx)

    return rx, ry, heading

def simulate(sess, steps=500, flip_steer=False):
    left, right, _ = make_track()
    x, y, heading = 0.0, 0.0, math.pi/2
    traj = []
    for _ in range(steps):
        rays_lmr = cast_rays(x, y, heading, left, right, max_range=10.0)
        steer, throttle = run_inference(sess, rays_lmr)
        if flip_steer:
            steer = -steer
        x, y, heading = step_with_collision(x, y, heading, steer, throttle, left, right, dt=0.15)
        traj.append((x, y, heading, rays_lmr, steer, throttle))
    return left, right, traj

def animate(sess, flip_steer=False):
    left, right, traj = simulate(sess, flip_steer=flip_steer)
    plt.ion()
    fig, ax = plt.subplots(figsize=(7, 7))
    ax.plot(left[:,0],  left[:,1],  'k-', lw=2)
    ax.plot(right[:,0], right[:,1], 'k-', lw=2)
    car, = ax.plot([], [], 'bo', ms=6)
    ray_lines = [ax.plot([], [], 'r-')[0] for _ in range(3)]
    ax.set_xlim(-12, 12); ax.set_ylim(-5, 60); ax.set_aspect('equal')

    fov = math.radians(90.0)
    angs = (+fov/2, 0.0, -fov/2)

    for (x, y, h, rays, steer, thr) in traj:
        car.set_data([x], [y])
        for line, a, d in zip(ray_lines, angs, rays):
            rx, ry = math.cos(h + a), math.sin(h + a)
            R = 10.0 * d
            line.set_data([x, x + rx*R], [y, y + ry*R])
        plt.pause(0.01)

    plt.ioff(); plt.show()


if __name__ == "__main__":
    sess = load_session("imit_nav_fast.onnx")
    animate(sess, flip_steer=False)

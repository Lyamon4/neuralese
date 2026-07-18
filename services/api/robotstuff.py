import ev3_dc as ev3
import time
import onnxruntime as ort
import numpy as np
import math

# ==========================================
# 1. КОНФИГУРАЦИЯ (HARDWARE SETUP)
# ==========================================

ROBOT_MAC = '00:16:53:5f:b4:33'  # <--- ВАШ MAC-АДРЕС СЮДА

# Сенсоры
PORT_RIGHT  = ev3.PORT_1   # правый
PORT_CENTER = ev3.PORT_2   # центральный
PORT_LEFT   = ev3.PORT_3   # левый

# Моторы
PORT_MOTOR_LEFT  = ev3.PORT_D
PORT_MOTOR_RIGHT = ev3.PORT_A

# Настройки поведения
MAX_SPEED     = 25
MODEL_PATH    = "imit_nav_fast.onnx"
RANGE_CM      = 100.0
TURN_GAIN     = 2.3
SCAN_FREQ_HZ  = 1.2
SCAN_AMP      = 0.15
SMOOTH_ALPHA  = 0.35
LOOP_DT       = 0.10

# AutoAssist
AVOID_GAIN    = 0.45
TIGHT_CM_1    = 40.0
TIGHT_CM_2    = 25.0

# Полный стоп / эскейп
HARD_STOP_CM  = 12.0
ESCAPE_CM     = 18.0
PWM_SCALE     = 7

print(f"--- ЗАПУСК REMOTE BRAIN ---")
print(f"Попытка соединения с {ROBOT_MAC}...")

try:
	# ==========================================
	# 2. ЗАГРУЗКА МОДЕЛИ
	# ==========================================
	print(f"Загрузка модели {MODEL_PATH} ...")
	session = ort.InferenceSession(MODEL_PATH, providers=["CPUExecutionProvider"])
	input_name = session.get_inputs()[0].name
	output_name = session.get_outputs()[0].name
	print("Модель успешно загружена.")

	# ==========================================
	# 3. СОЕДИНЕНИЕ С EV3
	# ==========================================
	with ev3.EV3(protocol=ev3.BLUETOOTH, host=ROBOT_MAC) as my_ev3:
		print(">> СВЯЗЬ УСТАНОВЛЕНА! <<")

		# Сенсоры
		sonar_right  = ev3.Ultrasonic(PORT_RIGHT,  protocol=ev3.BLUETOOTH, ev3_obj=my_ev3)
		sonar_center = ev3.Ultrasonic(PORT_CENTER, protocol=ev3.BLUETOOTH, ev3_obj=my_ev3)
		sonar_left   = ev3.Ultrasonic(PORT_LEFT,   protocol=ev3.BLUETOOTH, ev3_obj=my_ev3)

		# Моторы
		left_motor  = ev3.Motor(PORT_MOTOR_LEFT,  ev3_obj=my_ev3)
		right_motor = ev3.Motor(PORT_MOTOR_RIGHT, ev3_obj=my_ev3)

		print("3 датчика и моторы готовы. Нажмите Ctrl+C для выхода.")

		def decide_action(ray_left, ray_center, ray_right):
			x = np.array([[ray_left, ray_center, ray_right]], dtype=np.float32)
			y = session.run([output_name], {input_name: x})[0][0]
			steer, throttle = float(y[0]), float(y[1])
			return steer, throttle

		# безопасное чтение дистанции
		def safe_cm(sonar, prev=255.0):
			try:
				val = sonar.distance
				# Catch None, NaN, infinity, or absurd spikes
				if val is None or not math.isfinite(val) or val <= 0 or val > 300:
					return prev  # keep last valid
				return val * 10.0  # convert to cm
			except Exception as e:
				import traceback
				traceback.print_exc(e)
				return prev

		def safe_speed(x):
			x = int(round(x))
			if x < 1:
				return 0
			if x > 100:
				return 100
			return x

		prev_left, prev_center, prev_right = 255.0, 255.0, 255.0
		prev_steer_cmd = 0.0
		t0 = time.time()

		while True:
			start_time = time.time()

			# --- A. PERCEPTION ---
			dist_left   = safe_cm(sonar_left, prev_left)
			dist_center = safe_cm(sonar_center, prev_center)
			dist_right  = safe_cm(sonar_right, prev_right)
			prev_left, prev_center, prev_right = dist_left, dist_center, dist_right

			dist_min = min(dist_left, dist_center, dist_right)

			# Нормализация в 0..1
			ray_left   = max(0.0, min(1.0, dist_left / RANGE_CM))
			ray_center = max(0.0, min(1.0, dist_center / RANGE_CM))
			ray_right  = max(0.0, min(1.0, dist_right / RANGE_CM))

			# --- ЖЁСТКИЙ СТОП ---
			if dist_min <= HARD_STOP_CM:
				print(f"[STOP] Dmin={dist_min:.1f}cm — стоп")
				time.sleep(LOOP_DT)
				continue

			# --- ESCAPE TURN ---
			if dist_center <= ESCAPE_CM:
				turn_right = dist_left < dist_right
				spin_pwm = 60
				if turn_right:
					left_motor.start_move(speed=spin_pwm, direction=-1)
					right_motor.start_move(speed=spin_pwm, direction=+1)
					turn_txt = "RIGHT"
				else:
					left_motor.start_move(speed=spin_pwm, direction=+1)
					right_motor.start_move(speed=spin_pwm, direction=-1)
					turn_txt = "LEFT"
				print(f"[ESCAPE] D={dist_center:.1f}cm — spin {turn_txt}")
				time.sleep(LOOP_DT)
				continue

			# --- B. DECISION ---
			steer, throttle = decide_action(ray_left, ray_center, ray_right)

			# AutoAssist: уход от ближней стены
			steer += AVOID_GAIN * (ray_right - ray_left)

			# Коррекция по тесноте
			if dist_min < TIGHT_CM_2:
				steer *= 2.5
				throttle *= 0.5
			elif dist_min < TIGHT_CM_1:
				steer *= 2.0
				throttle *= 0.7

			# Auto-scan
			scan = math.sin(2.0 * math.pi * SCAN_FREQ_HZ * (time.time() - t0))
			steer += SCAN_AMP * scan

			# Сглаживание
			steer = SMOOTH_ALPHA * steer + (1 - SMOOTH_ALPHA) * prev_steer_cmd
			prev_steer_cmd = steer
			steer = max(-1.0, min(1.0, steer))
			throttle = max(0.0, min(1.0, throttle))

			# --- C. CONTROL ---
			s = TURN_GAIN * steer
			s = max(-1.0, min(1.0, s))

			v = throttle * MAX_SPEED
			v_l = v * (1.0 + s)
			v_r = v * (1.0 - s)

			if abs(v_l - v_r) > 0.7 * MAX_SPEED:
				v_l *= 0.85
				v_r *= 0.85

			sl = safe_speed(v_l * PWM_SCALE)
			sr = safe_speed(v_r * PWM_SCALE)

			# безопасное управление моторами
			if sl == 0 and sr == 0:
				print(f"[IDLE] — оба мотора в покое")
			else:
				try:
					if sl > 0:
						left_motor.start_move(speed=sl, direction=+1)
					if sr > 0:
						right_motor.start_move(speed=sr, direction=+1)
				except Exception as e:
					print(f"[WARN] Motor cmd skipped: {e}")

			# Лог
			def tag(d): return "∞" if d >= 254 else f"{d:.1f}"
			print(
				f"D[L,C,R]=[{tag(dist_left)},{tag(dist_center)},{tag(dist_right)}] cm | "
				f"Rays[{ray_left:.2f},{ray_center:.2f},{ray_right:.2f}] | "
				f"steer={steer:+.2f} thr={throttle:.2f} | L={v_l:.1f} R={v_r:.1f}"
			)

			elapsed = time.time() - start_time
			time.sleep(max(0.0, LOOP_DT - elapsed))

except KeyboardInterrupt:
	print("\nОстановка пользователем...")
	try:
		left_motor.stop_move()
		right_motor.stop_move()
	except:
		pass

except Exception as e:
	print(f"\nКРИТИЧЕСКАЯ ОШИБКА: {e}")

print("Соединение закрыто.")

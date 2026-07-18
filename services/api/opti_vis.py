import matplotlib.pyplot as plt
import numpy as np

# =========================
# Данные (N=16, batch=64)
# =========================
metrics = [
    "Запуски CUDA-ядер",
    "Средняя длительность ядра (мкс)",
    "Общее время GPU-ядер (мс)",
    "Memcpy (кол-во вызовов)",
    "Memset (кол-во вызовов)",
    "Доля топ-ядер (%)",
]

baseline = np.array([
    162_860,
    400,
    14_200,
    3_682,
    14_190,
    18,
], dtype=float)

fused = np.array([
    30_084,
    6_500,
    11_600,
    222,
    4_140,
    56,
], dtype=float)

# =========================
# Ручная нормализация
# =========================
scale = np.maximum(baseline, fused)
baseline_n = baseline / scale
fused_n = fused / scale

# =========================
# Построение графика
# =========================
x = np.arange(len(metrics))
width = 0.36

fig, ax = plt.subplots(figsize=(12, 5))

ax.bar(x - width/2, baseline_n, width, label="Baseline")
ax.bar(x + width/2, fused_n, width, label="TopoFuse")

ax.set_ylim(0, 1.08)
ax.set_ylabel("Нормализованное значение\n(максимум по метрике = 1.0)")
ax.set_title("Сравнение характеристик GPU\nBaseline vs TopoFuse (N=16, batch=64)")
ax.set_xticks(x)
ax.set_xticklabels(metrics, rotation=18, ha="right")
ax.legend(frameon=True)

# =========================
# Подписи абсолютных значений
# =========================
for i in range(len(metrics)):
    ax.text(
        x[i] - width/2,
        baseline_n[i] + 0,
        f"{baseline[i]:.0f}",
        ha="center",
        va="bottom",
        fontsize=9,
        rotation=0,
    )
    ax.text(
        x[i] + width/2,
        fused_n[i] + 0,
        f"{fused[i]:.0f}",
        ha="center",
        va="bottom",
        fontsize=9,
        rotation=0,
    )



# =========================
# Экспорт
# =========================
plt.savefig(
    "topofuse_gpu_comparison_n16.png",
    dpi=200,
    bbox_inches="tight",
)

plt.close()
print("✔ График сохранён: topofuse_gpu_comparison_n16.png")

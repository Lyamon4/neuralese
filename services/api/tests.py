import matplotlib.pyplot as plt
import pandas as pd
import numpy as np

# === данные ===
control = pd.DataFrame({
    "Понимание_до": [4,3,3,4,5,5,5,5,6,6],
    "Понимание_после": [5,4,4,4,6,5,5,7,7,7]
})
neuralese = pd.DataFrame({
    "Понимание_до": [3,4,3,4,5,5,5,5,6,6],
    "Понимание_после": [5,6,4,7,8,7,8,8,9,9]
})

# === частоты ===
def get_freqs(df):
    levels = range(1, 11)
    before = df["Понимание_до"].value_counts().reindex(levels, fill_value=0)
    after = df["Понимание_после"].value_counts().reindex(levels, fill_value=0)
    return levels, before.values, after.values

levels_c, before_c, after_c = get_freqs(control)
levels_n, before_n, after_n = get_freqs(neuralese)

# === универсальная функция ===
def plot_paired_bars(levels, before, after, title, filename):
    width = 0.4
    gap = 0.15  # расстояние между парами
    x = np.arange(len(levels)) * (2*width + gap)

    # каждая пара: синяя и зелёная колонка рядом
    plt.figure(figsize=(8,4))
    plt.bar(x, before, width, color="#1f77b4", label="До")
    plt.bar(x + width, after, width, color="#2ca02c", label="После")

    plt.xticks(x + width/2, levels)
    plt.xlabel("Уровень понимания")
    plt.ylabel("Количество учеников")
    plt.title(title)
    plt.legend()
    plt.grid(axis='y', alpha=0.3)

    plt.tight_layout()
    plt.savefig(filename, dpi=300, bbox_inches="tight")
    plt.show()

# === Построение и экспорт ===
plot_paired_bars(levels_c, before_c, after_c,
    "Контрольная группа: распределение уровней понимания", "control_understanding.png")

plot_paired_bars(levels_n, before_n, after_n,
    "Группа Neuralese: распределение уровней понимания", "neuralese_understanding.png")

import glob
import os
import re

import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import numpy as np
import pandas as pd
from matplotlib.patches import Patch

# ─── constants ──────────────────────────────────────────────────────────────

OUTPUT_DIR = "resultados_latencia"
WARMUP_ROWS = 1000  # discard SeqNum <= 1000

SCENARIO_ORDER = ["none", "auth", "encrypt", "access"]
SCENARIO_LABELS = {s: s.capitalize() for s in SCENARIO_ORDER}

PAYLOAD_LABELS = {256: "256 B", 1024: "1 KB", 16384: "16 KB"}

FILENAME_RE = re.compile(r"Latencia_(\w+)_(\d+)B_run(\d+)\.csv", re.IGNORECASE)


def payload_label(b: int) -> str:
    return PAYLOAD_LABELS.get(b, f"{b} B")


# ─── data loading ───────────────────────────────────────────────────────────


def load_all_runs() -> pd.DataFrame:
    """
    Scan OUTPUT_DIR for Latencia_*.csv files, parse metadata from the
    filename, strip warmup samples (SeqNum <= WARMUP_ROWS), and return
    a single concatenated DataFrame.
    """
    pattern = os.path.join(OUTPUT_DIR, "Latencia_*.csv")
    files = sorted(glob.glob(pattern))

    if not files:
        raise FileNotFoundError(
            f"No CSV files found matching '{pattern}'.\n"
            "Make sure the benchmark has been run and results are in "
            f"'{OUTPUT_DIR}/'."
        )

    frames = []
    for fpath in files:
        basename = os.path.basename(fpath)
        m = FILENAME_RE.search(basename)
        if not m:
            print(f"⚠️  Skipping unrecognised filename: {basename}")
            continue

        escenario = m.group(1).lower()
        payload_bytes = int(m.group(2))
        run_id = int(m.group(3))

        # Skip empty files early
        if os.path.getsize(fpath) == 0:
            print(f"⚠️  Skipping empty file: {basename}")
            continue

        try:
            df = pd.read_csv(fpath, on_bad_lines="skip")
        except Exception as exc:
            print(f"⚠️  Could not read {basename}: {exc}")
            continue

        # Validate required columns
        missing = {"SeqNum", "Latency_us"} - set(df.columns)
        if missing:
            print(f"⚠️  Missing columns {missing} in {basename} — skipping.")
            continue

        # Coerce numeric, drop unparseable rows
        df["SeqNum"] = pd.to_numeric(df["SeqNum"], errors="coerce")
        df["Latency_us"] = pd.to_numeric(df["Latency_us"], errors="coerce")
        df.dropna(subset=["SeqNum", "Latency_us"], inplace=True)

        # Drop warmup
        df = df[df["SeqNum"] > WARMUP_ROWS].copy()

        if df.empty:
            print(f"⚠️  No usable rows after warmup filter in {basename}.")
            continue

        df["Escenario"] = escenario
        df["PayloadBytes"] = payload_bytes
        df["RunID"] = run_id

        frames.append(df)

    if not frames:
        raise ValueError(
            "All CSV files were empty, invalid, or contained no post-warmup data."
        )

    combined = pd.concat(frames, axis=0, ignore_index=True)
    return combined


# ─── statistics ─────────────────────────────────────────────────────────────


def compute_summary(raw: pd.DataFrame) -> pd.DataFrame:
    """
    1. Compute per-run statistics (mean, median, p95, p99, std).
    2. Aggregate across runs by taking the mean of each statistic.
    Returns one row per (Escenario, PayloadBytes).
    """

    def per_run_stats(g: pd.DataFrame) -> pd.Series:
        lat = g["Latency_us"]
        return pd.Series(
            {
                "Mean_us": lat.mean(),
                "Median_us": lat.median(),
                "P95_us": lat.quantile(0.95),
                "P99_us": lat.quantile(0.99),
                "Std_us": lat.std(),
            }
        )

    run_stats = (
        raw.groupby(["Escenario", "PayloadBytes", "RunID"], sort=True)
        .apply(per_run_stats)
        .reset_index()
    )

    summary = (
        run_stats.groupby(["Escenario", "PayloadBytes"], sort=True)[
            ["Mean_us", "Median_us", "P95_us", "P99_us", "Std_us"]
        ]
        .mean()
        .reset_index()
    )

    return summary


# ─── plot helpers ───────────────────────────────────────────────────────────


def _ordered_scenarios(available) -> list:
    return [s for s in SCENARIO_ORDER if s in available]


def _ordered_payloads(available) -> list:
    return sorted(available)


# ─── plot 1: grouped bar chart ───────────────────────────────────────────────


def plot_mean_bar(summary: pd.DataFrame) -> None:
    """
    Grouped bar chart: mean latency (± std) by scenario for each payload size.
    Groups = payload sizes (x-axis), bars within each group = scenarios.
    """
    payloads = _ordered_payloads(summary["PayloadBytes"].unique())
    scenarios = _ordered_scenarios(summary["Escenario"].unique())

    n_s = len(scenarios)
    n_p = len(payloads)
    x = np.arange(n_p)
    width = 0.75 / n_s

    fig, ax = plt.subplots(figsize=(12, 6))
    colors = plt.cm.tab10.colors

    for i, esc in enumerate(scenarios):
        sub = summary[summary["Escenario"] == esc].set_index("PayloadBytes")
        means = [sub.loc[p, "Mean_us"] if p in sub.index else 0.0 for p in payloads]
        stds = [sub.loc[p, "Std_us"] if p in sub.index else 0.0 for p in payloads]
        offset = (i - n_s / 2 + 0.5) * width

        ax.bar(
            x + offset,
            means,
            width,
            label=SCENARIO_LABELS[esc],
            color=colors[i],
            yerr=stds,
            capsize=4,
            error_kw={"elinewidth": 1.2, "ecolor": "black", "alpha": 0.7},
            alpha=0.85,
        )

    ax.set_title(
        "Latencia Media por Escenario de Seguridad DDS",
        fontsize=14,
        fontweight="bold",
        pad=12,
    )
    ax.set_xlabel("Tamaño de Payload", fontsize=12)
    ax.set_ylabel("Latencia Media (µs)", fontsize=12)
    ax.set_xticks(x)
    ax.set_xticklabels([payload_label(p) for p in payloads], fontsize=11)
    ax.yaxis.set_minor_locator(mticker.AutoMinorLocator())
    ax.grid(axis="y", linestyle="--", alpha=0.5)
    ax.legend(title="Escenario", fontsize=10, title_fontsize=10)

    plt.tight_layout()
    out = "grafica_latencia_media.png"
    plt.savefig(out, dpi=300, bbox_inches="tight")
    plt.close()
    print(f"✅ Guardado: {out}")


# ─── plot 2: boxplot ─────────────────────────────────────────────────────────


def plot_boxplot(raw: pd.DataFrame) -> None:
    """
    Boxplot of raw (post-warmup) latency distribution.
    One subplot per payload size; within each subplot, one box per scenario.
    """
    payloads = _ordered_payloads(raw["PayloadBytes"].unique())
    scenarios = _ordered_scenarios(raw["Escenario"].unique())
    colors = plt.cm.tab10.colors

    n_p = len(payloads)
    fig, axes = plt.subplots(1, n_p, figsize=(5 * n_p, 6), sharey=False)
    if n_p == 1:
        axes = [axes]

    fig.suptitle(
        "Distribución de Latencia DDS por Escenario y Tamaño de Payload",
        fontsize=14,
        fontweight="bold",
    )

    for ax, p in zip(axes, payloads):
        data = [
            raw.loc[
                (raw["Escenario"] == esc) & (raw["PayloadBytes"] == p),
                "Latency_us",
            ]
            .dropna()
            .values
            for esc in scenarios
        ]

        bp = ax.boxplot(
            data,
            patch_artist=True,
            notch=False,
            medianprops={"color": "black", "linewidth": 2},
            flierprops={"marker": ".", "markersize": 2, "alpha": 0.4},
            whiskerprops={"linewidth": 1.4},
            capprops={"linewidth": 1.4},
        )

        for patch, color in zip(bp["boxes"], colors):
            patch.set_facecolor(color)
            patch.set_alpha(0.72)

        ax.set_title(f"Payload: {payload_label(p)}", fontsize=12, fontweight="bold")
        ax.set_xlabel("Escenario", fontsize=11)
        ax.set_ylabel("Latencia (µs)", fontsize=11)
        ax.set_xticks(range(1, len(scenarios) + 1))
        ax.set_xticklabels([SCENARIO_LABELS[s] for s in scenarios], fontsize=10)
        ax.yaxis.set_minor_locator(mticker.AutoMinorLocator())
        ax.grid(axis="y", linestyle="--", alpha=0.5)

    legend_elements = [
        Patch(facecolor=colors[i], alpha=0.72, label=SCENARIO_LABELS[s])
        for i, s in enumerate(scenarios)
    ]
    fig.legend(
        handles=legend_elements,
        title="Escenario",
        title_fontsize=10,
        fontsize=10,
        loc="lower center",
        ncol=len(scenarios),
        bbox_to_anchor=(0.5, -0.04),
    )

    plt.tight_layout()
    out = "grafica_latencia_boxplot.png"
    plt.savefig(out, dpi=300, bbox_inches="tight")
    plt.close()
    print(f"✅ Guardado: {out}")


# ─── plot 3: overhead line chart ─────────────────────────────────────────────


def plot_overhead(summary: pd.DataFrame) -> None:
    """
    Percentage overhead in mean latency relative to the 'none' baseline.
    One line per payload size; x-axis = security scenarios (auth, encrypt, access).
    """
    payloads = _ordered_payloads(summary["PayloadBytes"].unique())
    overhead_scenarios = [
        s for s in SCENARIO_ORDER if s != "none" and s in summary["Escenario"].unique()
    ]

    fig, ax = plt.subplots(figsize=(9, 6))
    colors = plt.cm.tab10.colors

    any_plotted = False
    for idx, p in enumerate(payloads):
        sub = summary[summary["PayloadBytes"] == p].set_index("Escenario")
        if "none" not in sub.index:
            print(
                f"⚠️  No 'none' baseline found for payload {payload_label(p)} — skipping overhead line."
            )
            continue

        baseline = sub.loc["none", "Mean_us"]
        if baseline == 0:
            print(
                f"⚠️  Baseline is 0 for payload {payload_label(p)} — skipping to avoid division by zero."
            )
            continue

        overheads = []
        for esc in overhead_scenarios:
            if esc in sub.index:
                pct = (sub.loc[esc, "Mean_us"] - baseline) / baseline * 100.0
            else:
                pct = 0.0
            overheads.append(pct)

        ax.plot(
            [SCENARIO_LABELS[s] for s in overhead_scenarios],
            overheads,
            marker="o",
            linewidth=2.2,
            markersize=8,
            color=colors[idx],
            label=payload_label(p),
        )
        any_plotted = True

    if not any_plotted:
        print("⚠️  No overhead data to plot (missing 'none' baseline for all payloads).")
        plt.close()
        return

    ax.axhline(0, color="gray", linestyle="--", linewidth=1, alpha=0.7)

    ax.set_title(
        "Overhead de Latencia vs. Escenario Sin Seguridad (none)",
        fontsize=14,
        fontweight="bold",
        pad=12,
    )
    ax.set_xlabel("Escenario de Seguridad", fontsize=12)
    ax.set_ylabel("Overhead de Latencia (%)", fontsize=12)
    ax.legend(title="Payload", fontsize=10, title_fontsize=10)
    ax.yaxis.set_minor_locator(mticker.AutoMinorLocator())
    ax.grid(linestyle="--", alpha=0.5)

    plt.tight_layout()
    out = "grafica_overhead.png"
    plt.savefig(out, dpi=300, bbox_inches="tight")
    plt.close()
    print(f"✅ Guardado: {out}")


# ─── main ───────────────────────────────────────────────────────────────────


def main() -> None:
    print("📊 Cargando datos de latencia…")
    raw = load_all_runs()
    print(
        f"   {len(raw):,} filas cargadas (primeras {WARMUP_ROWS} por corrida descartadas como calentamiento)."
    )

    print("📐 Calculando estadísticas por corrida y agregando…")
    summary = compute_summary(raw)

    # Save summary CSV
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    summary_path = os.path.join(OUTPUT_DIR, "resumen_estadistico.csv")
    summary[
        [
            "Escenario",
            "PayloadBytes",
            "Mean_us",
            "Median_us",
            "P95_us",
            "P99_us",
            "Std_us",
        ]
    ].to_csv(summary_path, index=False)
    print(f"✅ Resumen estadístico guardado: {summary_path}")

    # Print a quick preview
    print("\n── Resumen ──────────────────────────────────────────────────")
    preview = summary.copy()
    preview["Payload"] = preview["PayloadBytes"].map(payload_label)
    preview["Escenario"] = preview["Escenario"].map(SCENARIO_LABELS)
    print(
        preview[
            ["Escenario", "Payload", "Mean_us", "Median_us", "P95_us", "P99_us"]
        ].to_string(index=False, float_format=lambda x: f"{x:.1f}")
    )
    print()

    plt.style.use("seaborn-v0_8-whitegrid")

    print("🖼️  Generando gráficas…")
    plot_mean_bar(summary)
    plot_boxplot(raw)
    plot_overhead(summary)

    print("\n✅ ¡Todo listo! Las gráficas han sido guardadas en el directorio actual.")


if __name__ == "__main__":
    main()

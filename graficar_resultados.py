import glob
import os

import matplotlib.pyplot as plt
import pandas as pd


def generar_graficas():
    path = "resultados_latencia"
    all_files = glob.glob(os.path.join(path, "*.csv"))

    if not all_files:
        print("❌ No se encontraron archivos de resultados.")
        return

    li = []
    for filename in all_files:
        try:
            # Validar que el archivo no esté vacío
            if os.stat(filename).st_size == 0:
                continue
            df = pd.read_csv(filename, index_col=None, header=0)
            li.append(df)
        except Exception as e:
            print(f"⚠️ Error procesando {filename}: {e}")

    if not li:
        return

    frame = pd.concat(li, axis=0, ignore_index=True)

    # Mejoras estéticas para el documento de tesis
    plt.figure(figsize=(12, 7))
    plt.style.use("seaborn-v0_8-whitegrid")

    try:
        # Ejemplo: Boxplot por escenario
        frame.boxplot(column="Latencia_us", by="Escenario")
        plt.title("Comparativa de Latencia por Escenario de Seguridad")
        plt.suptitle("")  # Quitar título automático de pandas
        plt.ylabel("Latencia (µs)")
        plt.xlabel("Configuración de Seguridad")

        plt.savefig("grafica_latencia_dds.png", dpi=300, bbox_inches="tight")
        print("✅ Gráfica guardada como grafica_latencia_dds.png")
    except Exception as e:
        print(f"❌ Error al generar la gráfica: {e}")


if __name__ == "__main__":
    generar_graficas()

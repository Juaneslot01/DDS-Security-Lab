import glob
import os

import matplotlib.pyplot as plt
import pandas as pd
import seaborn as sns

# Configuración de estilo
sns.set_theme(style="whitegrid")
plt.figure(figsize=(12, 7))

# Buscar todos los archivos .csv en la carpeta
archivos = glob.glob("resultados_csv/*.csv")

if not archivos:
    print("❌ No se encontraron archivos CSV en la carpeta 'resultados_csv'")
    exit()

all_data = []

for archivo in archivos:
    try:
        # LEER Y LIMPIAR:
        # leemos el archivo y forzamos a que solo tome las columnas que queremos.
        # on_bad_lines='skip' ignora automáticamente las líneas de texto del encabezado de FastDDS.
        df = pd.read_csv(
            archivo,
            names=["SeqNum", "PayloadSize", "Latency"],
            on_bad_lines="skip",
            engine="python",
        )

        # Convertir a numérico y borrar filas que quedaron con texto (NaN)
        df["Latency"] = pd.to_numeric(df["Latency"], errors="coerce")
        df = df.dropna(subset=["Latency"])

        # Extraer el nombre de la prueba para la leyenda
        nombre_prueba = os.path.basename(archivo).replace(".csv", "")
        df["Prueba"] = nombre_prueba

        all_data.append(df)
        print(f"✅ Procesado: {nombre_prueba} ({len(df)} muestras)")

    except Exception as e:
        print(f"⚠️ Error procesando {archivo}: {e}")

# Unir todos los datos
if all_data:
    df_final = pd.concat(all_data, ignore_index=True)

    # Crear el Boxplot
    ax = sns.boxplot(x="Prueba", y="Latency", data=df_final)
    plt.title("Comparativa de Latencia por Tamaño de Payload", fontsize=15)
    plt.ylabel("Latencia (microsegundos)", fontsize=12)
    plt.xlabel("Configuración de Prueba", fontsize=12)

    # Guardar la gráfica
    plt.savefig("grafica_latencia_dds.png")
    print("\n🎉 Gráfica generada con éxito: grafica_latencia_dds.png")
    plt.show()

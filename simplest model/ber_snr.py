import pandas as pd
import matplotlib.pyplot as plt
import numpy as np

# Загрузка данных
df = pd.read_csv('Data/statistics.csv', skipinitialspace=True)

# Убираем возможные дубликаты заголовков в данных
df = df[df['FolderID'].astype(str).str.isdigit()]

# Преобразуем колонки к числовому типу
numeric_cols = ['SNR', 'MS_SNR', 'BER', 'FEC_BER', 'ID_BER', 'RMSE', 'ID_RMSE']
df[numeric_cols] = df[numeric_cols].astype(float)

# Группируем по SNR и усредняем BER
ber_vs_snr = df.groupby('SNR')['BER'].mean().reset_index()

# Сортируем по SNR
ber_vs_snr = ber_vs_snr.sort_values('SNR', ascending=False)
print(ber_vs_snr)
# Построение графика
plt.figure(figsize=(10, 6))
plt.semilogy(ber_vs_snr['SNR'], ber_vs_snr['BER'], marker='o', linestyle='-', linewidth=2, markersize=8, color='b')
plt.xlabel('SNR (dB)', fontsize=12)
plt.ylabel('BER (log scale)', fontsize=12)
plt.title('Зависимость BER от SNR', fontsize=14)
plt.grid(True, which='both', linestyle='--', linewidth=0.5)
plt.xticks(ber_vs_snr['SNR'])
plt.tight_layout()
plt.show()

# Для наглядности также выведем таблицу значений
print(ber_vs_snr)
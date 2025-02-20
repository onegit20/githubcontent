import pandas as pd
excel = 'D:\\Users\\2306155002\\Downloads\\价格表.xlsx'
data = pd.read_excel(excel, dtype={'代码': str})
data['价格'] = pd.to_numeric(data['价格'], errors='coerce')
data = data.dropna(subset=['价格'])
data_top5 = data.sort_values(['所属行业', '价格'], ascending=[False, False]).groupby('所属行业').head(5)

with pd.ExcelWriter(excel, engine='openpyxl', mode='a') as ew:
    if 'top5' not in ew.sheets:
        data_top5.to_excel(ew, sheet_name='top5', index=False)
    else:
        print('top5 already exists!')

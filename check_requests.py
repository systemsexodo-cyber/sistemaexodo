import zipfile

p = r'dist\SincronizadorNuvem\_internal\base_library.zip'
z = zipfile.ZipFile(p)
names = z.namelist()
print('base_library has requests:', any('requests' in n for n in names))
print('goog_crc:', [n for n in names if 'google' in n][:3])

p2 = r'build\SincronizadorNuvem\PYZ-00.pyz'
try:
    z2 = zipfile.ZipFile(p2)
    names2 = z2.namelist()
    print('pyz has requests:', any('requests' in n for n in names2))
    print([n for n in names2 if 'requests' in n][:10])
except Exception as e:
    print('pyz error', e)

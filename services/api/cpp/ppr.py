import os
import sys


path = os.getcwd() + "/src/" + (sys.argv[1] if len(sys.argv) >1 else "")
res = open("res_ppr.txt", "w+", encoding="utf-8")
res.write("")
res.seek(0)
def applog(what: str):
	print(what)
	res.writelines(what)
for i in os.listdir(path):
	i = path + i
	if ".cpp" in i or ".h" in i:
		applog(f"===== FILE: {i} ======")
		applog(open(i, encoding="utf-8").read())
	else:
		applog(f"===== DIR: {i} ======")
with open("AppDelegate.swift", "r") as f:
    lines = f.readlines()

new_lines = []
skip = False
for line in lines:
    if line.startswith("<<<<<<< HEAD"):
        pass
    elif line.startswith("======="):
        skip = True
    elif line.startswith(">>>>>>> dcc6b560f94e1f92c12f88df0e8fa30c045fcabf"):
        skip = False
    elif not skip:
        new_lines.append(line)

with open("AppDelegate.swift", "w") as f:
    f.writelines(new_lines)

from setuptools import setup
from torch.utils.cpp_extension import CppExtension, BuildExtension
import os
os.environ["DISTUTILS_USE_SDK"] = "1"

CUDA_HOME = r"C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.1"

setup(
	name="neuralese_ops",
	ext_modules=[
		CppExtension(
			name="neuralese_ops",
			sources=[
				"src/binding.cpp",
				"src/executor.cpp",
				"src/ops.cpp",
			],
			include_dirs=[
				os.path.join(CUDA_HOME, "include"),
			],
			library_dirs=[
				os.path.join(CUDA_HOME, "lib", "x64"),
			],
			extra_compile_args={
				"cxx": ["/O2"],
			},
		)
	],
	cmdclass={"build_ext": BuildExtension},
)

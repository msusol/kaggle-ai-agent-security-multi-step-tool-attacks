from setuptools import setup, find_packages
setup(
    name="aicomp_sdk",
    version="3.1.0.dev0",
    packages=find_packages(include=["aicomp_sdk", "aicomp_sdk.*"]),
    package_data={"aicomp_sdk": ["fixtures/*.json"]},
    python_requires=">=3.10",
)

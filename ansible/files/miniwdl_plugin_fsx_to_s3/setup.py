from setuptools import setup, find_packages

setup(
    name='miniwdl_plugin_fsx_to_s3',
    version='0.0.1',
    description='miniwdl-cloud fsx_to_s3 plugin',
    author='Wid L. Hacker',
    py_modules=["miniwdl_plugin_fsx_to_s3"],
    python_requires='>=3.6',
    setup_requires=['reentry'],
    install_requires=[],
    reentry_register=True,
    entry_points={
        'miniwdl.plugin.task': ['task_fsx_to_s3 = miniwdl_plugin_fsx_to_s3:task'],
        'miniwdl.plugin.workflow': ['workflow_fsx_to_s3 = miniwdl_plugin_fsx_to_s3:workflow'],
    }
)

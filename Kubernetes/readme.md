# Install virtual environment
python3 -m venv xtesting_env
source xtesting_env/bin/activate

# Install Xtesting
pip install xtesting

# Run 
xtesting run xtesting_free5gc_parallel.yaml --log free5gc_parallel.log

#!/bin/bash
python --version
python -c "import numpy; print(\"numpy\", numpy.__version__)"
python -c "import matplotlib; print(\"matplotlib\", matplotlib.__version__)"
python -c "import seaborn; print(\"seaborn\", seaborn.__version__)"
fastqc --version
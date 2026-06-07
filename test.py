import os

import tensorflow as tf

p = "PATH/TO/your_flutter_project/assets/defendra_int8.tflite"
print("file size on disk:", os.path.getsize(p))   # expect ~131–137 MB
interp = tf.lite.Interpreter(p); interp.allocate_tensors()
print("tensor 120:", interp._get_tensor_details(120)["name"],
      interp.tensor(120)().nbytes, "bytes")        # must be non-zero (~91 MB)
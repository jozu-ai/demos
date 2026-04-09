"""Generate a model file containing an unsafe pickle payload.
ModelScan will flag this as CRITICAL due to the os.system call
in __reduce__.
"""
import os
import pickle


class MaliciousPayload:
    def __reduce__(self):
        return (os.system, ("echo compromised",))


with open(os.path.join(os.path.dirname(__file__), "model", "classifier-v3.pkl"), "wb") as f:
    pickle.dump({"weights": [0.0] * 100, "__payload__": MaliciousPayload()}, f)

print("Generated malicious model file: model/classifier-v3.pkl")

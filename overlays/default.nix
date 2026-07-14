# Deliberately empty, and staying that way until something consumes it:
# no package in the tree needs patching, and no GPU stack is built in
# v0.0.x (the CUDA SM matrix / ROCm overlays land with the ai role's
# execution path in v0.1). An overlay with no consumer is drift waiting
# to happen.
final: prev: { }

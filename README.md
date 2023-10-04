# zig-capnp
Yet another capnproto code generator attempt for zig

## Progress

We are currently in early stages of development. This is not a useful project yet!

The current status is that code generation is working for schema.capnp to the point we can replace our hand-written schema file

- [x] Minimal reading
- [x] Reading of capnproto
- [ ] Code generation (Reader)
- [ ] Code generation (Builder)
- [ ] Packed messages
- [ ] RPC

## Existing efforts

### Zarzwick/capnproto-zig

Gitlab: https://gitlab.com/Zarzwick/capnproto-zig/-/tree/main

This appears the most advanced of existing efforts. The compiler is implemented in C++, not zig.

I do not seem to be able to find the alternative efforts!


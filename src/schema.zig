const capnp = @import("capnp.zig");

pub const Field = struct {
    pub const Reader = struct {
        reader: capnp.StructReader,

        pub fn getName(self: @This()) []u8 {
            return self.reader.readStringField(0);
        }
    };
};
pub const Node = struct {
    pub const _Tag = union(enum) {
        const FileReader = struct {
            reader: capnp.StructReader,
        };

        const StructReader = struct {
            reader: capnp.StructReader,

            pub fn getFields(self: @This()) capnp.CompositeListReader(Field) {
                return self.reader.readCompositeListField(Field, 3);
            }
        };

        file: FileReader,
        struct_: StructReader,
        enum_,
        const_,
        interface,
        annotation,
        _other: u16,
    };

    pub const NestedNode = struct {
        pub const Reader = struct {
            reader: capnp.StructReader,

            pub fn getId(self: @This()) u64 {
                return self.reader.readIntField(u64, 0);
            }

            pub fn getName(self: @This()) []u8 {
                return self.reader.readStringField(0);
            }
        };
    };
    pub const Reader = struct {
        reader: capnp.StructReader,

        pub fn which(self: Reader) _Tag {
            const n = self.reader.readIntField(u16, 6);
            switch (n) {
                0 => {
                    return _Tag{ .file = _Tag.FileReader{ .reader = self.reader } };
                },
                1 => {
                    return _Tag{ .struct_ = _Tag.StructReader{ .reader = self.reader } };
                },
                2 => {
                    return _Tag.enum_;
                },
                3 => {
                    return _Tag.interface;
                },
                4 => {
                    return _Tag.const_;
                },
                5 => {
                    return _Tag.annotation;
                },
                else => {
                    return _Tag{ ._other = n };
                },
            }
        }

        pub fn getId(self: Reader) u64 {
            return self.reader.readIntField(u64, 0);
        }

        pub fn getDisplayName(self: Reader) []u8 {
            return self.reader.readStringField(0);
        }

        pub fn getNestedNodes(self: @This()) capnp.CompositeListReader(Node.NestedNode) {
            return self.reader.readCompositeListField(Node.NestedNode, 1);
        }
    };
};

pub const CodeGeneratorRequest = struct {
    pub const RequestedFile = struct {
        pub const Reader = struct {
            reader: capnp.StructReader,

            pub fn getId(self: @This()) u64 {
                return self.reader.readIntField(u64, 0);
            }
        };
    };
    pub const Reader = struct {
        reader: capnp.StructReader,

        pub fn getNodes(self: @This()) capnp.CompositeListReader(Node) {
            return self.reader.readCompositeListField(Node, 0);
        }

        pub fn getRequestedFiles(self: @This()) capnp.CompositeListReader(CodeGeneratorRequest.RequestedFile) {
            return self.reader.readCompositeListField(CodeGeneratorRequest.RequestedFile, 1);
        }
    };
};

const capnp = @import("capnp.zig");
const std = @import("std");
pub const Type = struct {
    const Tag = union(enum) {
        pub const List = struct {
            reader: capnp.StructReader,
            pub fn getElementType(self: @This()) !Type.Reader {
                return .{ .reader = try self.reader.readPtrField(capnp.StructReader, 0) };
            }
        };

        pub const Enum = struct {
            reader: capnp.StructReader,

            pub fn getTypeId(self: @This()) u64 {
                return self.reader.readIntField(u64, 1);
            }
        };

        pub const Struct = struct {
            reader: capnp.StructReader,

            pub fn getId(self: @This()) u64 {
                return self.reader.readIntField(u64, 1);
            }
        };

        pub const AnyPointer = struct {
            reader: capnp.StructReader,
        };

        pub const Interface = struct {
            reader: capnp.StructReader,
        };

        void,
        bool,
        int8,
        int16,
        int32,
        int64,
        uint8,
        uint16,
        uint32,
        uint64,
        float32,
        float64,
        text,
        data,
        list: List,
        enum_: Enum,
        struct_: Struct,
        interface: Interface,
        anyPointer: AnyPointer,
        _other: u16,

        pub fn toString(self: Tag) []const u8 {
            return switch (self) {
                else => |x| @tagName(x),
            };
        }
    };

    pub const Reader = struct {
        reader: capnp.StructReader,

        pub fn which(self: @This()) capnp.Counter.Error!Type.Tag {
            return switch (self.reader.readIntField(u16, 0)) {
                0 => .void,
                1 => .bool,
                2 => .int8,
                3 => .int16,
                4 => .int32,
                5 => .int64,
                6 => .uint8,
                7 => .uint16,
                8 => .uint32,
                9 => .uint64,
                10 => .float32,
                11 => .float64,
                12 => .text,
                13 => .data,
                14 => .{ .list = .{ .reader = self.reader } },
                15 => .{ .enum_ = .{ .reader = self.reader } },
                16 => .{ .struct_ = .{ .reader = self.reader } },
                17 => .{ .interface = .{ .reader = self.reader } },
                18 => .{ .anyPointer = .{ .reader = self.reader } },
                else => |n| .{ ._other = n },
            };
        }
    };
};

pub const Value = struct {
    pub const Reader = struct {
        reader: capnp.StructReader,

        pub const _Tag = union(enum) {
            void,
            bool: bool,
            int8: i8,
            int16: i16,
            int32: i32,
            int64: u64,
            uint8: u8,
            uint16: u16,
            uint32: u32,
            uint64: u64,
            float32: f32,
            float64: f64,
            text: []const u8,
            data: []const u8,
            list: capnp.AnyPointer,
            enum_: u16,
            struct_: capnp.AnyPointer,
            interface,
            anyPointer: capnp.AnyPointer,
        };

        pub fn which(self: @This()) capnp.Counter.Error!_Tag {
            return switch (self.reader.readIntField(u16, 0)) {
                0 => _Tag{ .void = void{} },
                1 => _Tag{ .bool = self.reader.readBoolField(16) },
                2 => _Tag{ .int8 = self.reader.readIntField(i8, 2) },
                3 => _Tag{ .int16 = self.reader.readIntField(i16, 1) },
                4 => _Tag{ .int32 = self.reader.readIntField(i32, 1) },
                5 => _Tag{ .int64 = self.reader.readIntField(i64, 1) },
                6 => _Tag{ .uint8 = self.reader.readIntField(u8, 2) },
                7 => _Tag{ .uint16 = self.reader.readIntField(u16, 1) },
                8 => _Tag{ .uint32 = self.reader.readIntField(u32, 1) },
                9 => _Tag{ .uint64 = self.reader.readIntField(u64, 1) },
                10 => _Tag{ .float32 = self.reader.readFloatField(f32, 1) },
                11 => _Tag{ .float64 = self.reader.readFloatField(f64, 1) },
                12 => _Tag{ .text = self.reader.readStringField(0) },
                13 => _Tag{ .data = self.reader.readStringField(0) },
                14 => _Tag{ .list = self.reader.readPtrField(capnp.AnyPointerReader) },
                15 => _Tag{ .enum_ = self.reader.readIntField(u16, 1) },
                16 => _Tag{ .struct_ = self.reader.readPtrField(capnp.AnyPointerReader) },
                17 => _Tag{ .interface = void{} },
                18 => _Tag{ .anyPointer = self.reader.readPtrField(capnp.AnyPointerReader) },
                else => |n| .{ ._other = n },
            };
        }
    };
};

pub const Field = struct {
    pub const _Tag = union(enum) {
        const Slot = struct {
            reader: capnp.StructReader,

            pub fn getType(self: @This()) !Type.Reader {
                return .{ .reader = try self.reader.readPtrField(capnp.StructReader, 2) };
            }

            pub fn getOffset(self: @This()) u32 {
                return self.reader.readIntField(u32, 1);
            }

            pub fn getDefaultValue(self: @This()) capnp.Error!Value {
                _ = self;
            }
        };
        const Group = struct {
            reader: capnp.StructReader,

            pub fn getId(self: @This()) u64 {
                return self.reader.readIntField(u64, 2);
            }
        };

        slot: Slot,
        group: Group,
        _other: u16,
    };
    pub const Reader = struct {
        reader: capnp.StructReader,

        pub fn which(self: @This()) capnp.Counter.Error!Field._Tag {
            switch (self.reader.readIntField(u16, 4)) {
                0 => {
                    return Field._Tag{ .slot = .{ .reader = self.reader } };
                },
                1 => {
                    return Field._Tag{ .group = .{ .reader = self.reader } };
                },
                else => |n| {
                    return Field._Tag{ ._other = n };
                },
            }
        }

        pub fn getDiscriminantValue(self: @This()) u16 {
            return self.reader.readIntField(u16, 1) ^ 65535;
        }

        pub fn getName(self: @This()) ![]u8 {
            return self.reader.readStringField(0);
        }
    };
};
pub const Node = struct {
    pub const _Tag = union(enum) {
        const File = struct {
            reader: capnp.StructReader,
        };

        const Struct = struct {
            reader: capnp.StructReader,

            pub fn getFields(self: @This()) capnp.Counter.Error!capnp.CompositeListReader(Field) {
                return self.reader.readPtrField(capnp.CompositeListReader(Field), 3);
            }

            pub fn getDiscriminantCount(self: @This()) u16 {
                return self.reader.readIntField(u16, 240 / 16);
            }
        };

        file: @This().File,
        struct_: @This().Struct,
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

            pub fn getName(self: @This()) ![]u8 {
                return self.reader.readStringField(0);
            }
        };
    };
    pub const Reader = struct {
        reader: capnp.StructReader,

        pub fn which(self: @This()) capnp.Counter.Error!_Tag {
            const n = self.reader.readIntField(u16, 6);
            switch (n) {
                0 => {
                    return _Tag{ .file = .{ .reader = self.reader } };
                },
                1 => {
                    return _Tag{ .struct_ = .{ .reader = self.reader } };
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

        pub fn getDisplayName(self: Reader) capnp.Counter.Error![]u8 {
            return self.reader.readStringField(0);
        }

        pub fn getDisplayNamePrefixLength(self: Reader) u32 {
            return self.reader.readIntField(u32, 2);
        }

        pub fn getScopeId(self: Reader) u64 {
            return self.reader.readIntField(u64, 2);
        }

        pub fn getNestedNodes(self: @This()) capnp.Counter.Error!capnp.CompositeListReader(Node.NestedNode) {
            return self.reader.readPtrField(capnp.CompositeListReader(Node.NestedNode), 1);
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

        pub fn getNodes(self: @This()) capnp.Counter.Error!capnp.CompositeListReader(Node) {
            return self.reader.readPtrField(capnp.CompositeListReader(Node), 0);
        }

        pub fn getRequestedFiles(self: @This()) capnp.Counter.Error!capnp.CompositeListReader(CodeGeneratorRequest.RequestedFile) {
            return self.reader.readPtrField(capnp.CompositeListReader(CodeGeneratorRequest.RequestedFile), 1);
        }
    };
};

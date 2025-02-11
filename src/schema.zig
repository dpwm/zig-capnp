const std = @import("std");
const capnp = @import("capnp.zig");
const _Root = @This();

pub const Node = struct {
    const id: u64 = 0xe682ab4cf923a417;

    pub const struct_ = struct {
        const id: u64 = 0x9ea0b19b37fb4435;

        pub const _Group = struct {};

        pub const Reader = struct {
            reader: capnp.StructReader,

            pub fn getDataWordCount(self: @This()) u16 {
                return self.reader.readIntField(u16, 7) ^ 0;
            }

            pub fn getPointerCount(self: @This()) u16 {
                return self.reader.readIntField(u16, 12) ^ 0;
            }

            pub fn getPreferredListEncoding(self: @This()) _Root.ElementSize {
                return @enumFromInt(self.reader.readIntField(u16, 13) ^ 0);
            }

            pub fn getIsGroup(self: @This()) bool {
                return self.reader.readBoolField(224);
            }

            pub fn getDiscriminantCount(self: @This()) u16 {
                return self.reader.readIntField(u16, 15) ^ 0;
            }

            pub fn getDiscriminantOffset(self: @This()) u32 {
                return self.reader.readIntField(u32, 8) ^ 0;
            }

            pub fn getFields(self: @This()) capnp.Error!capnp.CompositeListReader(_Root.Field) {
                return try self.reader.readPtrField(capnp.CompositeListReader(_Root.Field), 3);
            }
        };
    };

    pub const enum_ = struct {
        const id: u64 = 0xb54ab3364333f598;

        pub const _Group = struct {};

        pub const Reader = struct {
            reader: capnp.StructReader,

            pub fn getEnumerants(self: @This()) capnp.Error!capnp.CompositeListReader(_Root.Enumerant) {
                return try self.reader.readPtrField(capnp.CompositeListReader(_Root.Enumerant), 3);
            }
        };
    };

    pub const interface = struct {
        const id: u64 = 0xe82753cff0c2218f;

        pub const _Group = struct {};

        pub const Reader = struct {
            reader: capnp.StructReader,

            pub fn getMethods(self: @This()) capnp.Error!capnp.CompositeListReader(_Root.Method) {
                return try self.reader.readPtrField(capnp.CompositeListReader(_Root.Method), 3);
            }

            pub fn getSuperclasses(self: @This()) capnp.Error!capnp.CompositeListReader(_Root.Superclass) {
                return try self.reader.readPtrField(capnp.CompositeListReader(_Root.Superclass), 4);
            }
        };
    };

    pub const const_ = struct {
        const id: u64 = 0xb18aa5ac7a0d9420;

        pub const _Group = struct {};

        pub const Reader = struct {
            reader: capnp.StructReader,

            pub fn getType(self: @This()) capnp.Error!_Root.Type.Reader {
                return .{ .reader = try self.reader.readPtrField(capnp.StructReader, 3) };
            }

            pub fn getValue(self: @This()) capnp.Error!_Root.Value.Reader {
                return .{ .reader = try self.reader.readPtrField(capnp.StructReader, 4) };
            }
        };
    };

    pub const annotation = struct {
        const id: u64 = 0xec1619d4400a0290;

        pub const _Group = struct {};

        pub const Reader = struct {
            reader: capnp.StructReader,

            pub fn getType(self: @This()) capnp.Error!_Root.Type.Reader {
                return .{ .reader = try self.reader.readPtrField(capnp.StructReader, 3) };
            }

            pub fn getTargetsFile(self: @This()) bool {
                return self.reader.readBoolField(112);
            }

            pub fn getTargetsConst(self: @This()) bool {
                return self.reader.readBoolField(113);
            }

            pub fn getTargetsEnum(self: @This()) bool {
                return self.reader.readBoolField(114);
            }

            pub fn getTargetsEnumerant(self: @This()) bool {
                return self.reader.readBoolField(115);
            }

            pub fn getTargetsStruct(self: @This()) bool {
                return self.reader.readBoolField(116);
            }

            pub fn getTargetsField(self: @This()) bool {
                return self.reader.readBoolField(117);
            }

            pub fn getTargetsUnion(self: @This()) bool {
                return self.reader.readBoolField(118);
            }

            pub fn getTargetsGroup(self: @This()) bool {
                return self.reader.readBoolField(119);
            }

            pub fn getTargetsInterface(self: @This()) bool {
                return self.reader.readBoolField(120);
            }

            pub fn getTargetsMethod(self: @This()) bool {
                return self.reader.readBoolField(121);
            }

            pub fn getTargetsParam(self: @This()) bool {
                return self.reader.readBoolField(122);
            }

            pub fn getTargetsAnnotation(self: @This()) bool {
                return self.reader.readBoolField(123);
            }
        };
    };

    pub const parameter = struct {
        const id: u64 = 0xb9521bccf10fa3b1;

        pub const _Group = struct {};

        pub const Reader = struct {
            reader: capnp.StructReader,

            pub fn getName(self: @This()) capnp.Error![]const u8 {
                return try self.reader.readStringField(0);
            }
        };
    };

    pub const NestedNode = struct {
        const id: u64 = 0xdebf55bbfa0fc242;

        pub const _Group = struct {};

        pub const Reader = struct {
            reader: capnp.StructReader,

            pub fn getName(self: @This()) capnp.Error![]const u8 {
                return try self.reader.readStringField(0);
            }

            pub fn getId(self: @This()) u64 {
                return self.reader.readIntField(u64, 0) ^ 0;
            }
        };
    };

    pub const SourceInfo = struct {
        const id: u64 = 0xf38e1de3041357ae;

        pub const _Group = struct {};

        pub const Member = struct {
            const id: u64 = 0xc2ba9038898e1fa2;

            pub const _Group = struct {};

            pub const Reader = struct {
                reader: capnp.StructReader,

                pub fn getDocComment(self: @This()) capnp.Error![]const u8 {
                    return try self.reader.readStringField(0);
                }
            };
        };

        pub const Reader = struct {
            reader: capnp.StructReader,

            pub fn getId(self: @This()) u64 {
                return self.reader.readIntField(u64, 0) ^ 0;
            }

            pub fn getDocComment(self: @This()) capnp.Error![]const u8 {
                return try self.reader.readStringField(0);
            }

            pub fn getMembers(self: @This()) capnp.Error!capnp.CompositeListReader(_Root.Node.SourceInfo.Member) {
                return try self.reader.readPtrField(capnp.CompositeListReader(_Root.Node.SourceInfo.Member), 1);
            }
        };
    };

    pub const Tag = enum(u16) {
        file,
        @"struct",
        @"enum",
        interface,
        @"const",
        annotation,
        _,
    };

    pub const Reader = struct {
        reader: capnp.StructReader,

        pub fn which(self: @This()) Tag {
            return @enumFromInt(self.reader.readIntField(u16, 6));
        }

        pub fn getStruct(self: @This()) ?struct_.Reader {
            return .{ .reader = self.reader };
        }

        pub fn getId(self: @This()) u64 {
            return self.reader.readIntField(u64, 0) ^ 0;
        }

        pub fn getEnum(self: @This()) ?enum_.Reader {
            return .{ .reader = self.reader };
        }

        pub fn getDisplayName(self: @This()) capnp.Error![]const u8 {
            return try self.reader.readStringField(0);
        }

        pub fn getDisplayNamePrefixLength(self: @This()) u32 {
            return self.reader.readIntField(u32, 2) ^ 0;
        }

        pub fn getScopeId(self: @This()) u64 {
            return self.reader.readIntField(u64, 2) ^ 0;
        }

        pub fn getNestedNodes(self: @This()) capnp.Error!capnp.CompositeListReader(_Root.Node.NestedNode) {
            return try self.reader.readPtrField(capnp.CompositeListReader(_Root.Node.NestedNode), 1);
        }

        pub fn getAnnotations(self: @This()) capnp.Error!capnp.CompositeListReader(_Root.Annotation) {
            return try self.reader.readPtrField(capnp.CompositeListReader(_Root.Annotation), 2);
        }

        pub fn getParameters(self: @This()) capnp.Error!capnp.CompositeListReader(_Root.Node.Parameter) {
            return try self.reader.readPtrField(capnp.CompositeListReader(_Root.Node.Parameter), 5);
        }

        pub fn getIsGeneric(self: @This()) bool {
            return self.reader.readBoolField(288);
        }
    };
};

pub const Field = struct {
    const id: u64 = 0x9aad50a41f4af45f;

    pub const Tag = enum(u16) {
        slot,
        group,
        _,
    };

    pub const slot = struct {
        const id: u64 = 0xc42305476bb4746f;

        pub const _Group = struct {};

        pub const Reader = struct {
            reader: capnp.StructReader,

            pub fn getOffset(self: @This()) u32 {
                return self.reader.readIntField(u32, 1) ^ 0;
            }

            pub fn getType(self: @This()) capnp.Error!_Root.Type.Reader {
                return .{ .reader = try self.reader.readPtrField(capnp.StructReader, 2) };
            }

            pub fn getDefaultValue(self: @This()) capnp.Error!_Root.Value.Reader {
                return .{ .reader = try self.reader.readPtrField(capnp.StructReader, 3) };
            }

            pub fn getHadExplicitDefault(self: @This()) bool {
                return self.reader.readBoolField(128);
            }
        };
    };

    pub const group = struct {
        const id: u64 = 0xcafccddb68db1d11;

        pub const _Group = struct {};

        pub const Reader = struct {
            reader: capnp.StructReader,

            pub fn getTypeId(self: @This()) u64 {
                return self.reader.readIntField(u64, 2) ^ 0;
            }
        };
    };

    pub const ordinal = struct {
        const id: u64 = 0xbb90d5c287870be6;

        pub const _Group = struct {};

        pub const Reader = struct {
            reader: capnp.StructReader,

            pub const _Tag = union(enum) {
                implicit: void,
                explicit: u16,
                _: u16,
            };

            pub fn which(self: @This()) capnp.Error!_Tag {
                return switch (self.reader.readIntField(u16, 5)) {
                    0 => _Tag{ .implicit = void{} },
                    1 => _Tag{ .explicit = self.reader.readIntField(u16, 6) ^ 0 },
                    else => |n| _Tag{ ._ = n },
                };
            }
        };
    };

    pub const Reader = struct {
        reader: capnp.StructReader,

        pub fn which(self: @This()) Field.Tag {
            return @enumFromInt(self.reader.readIntField(u16, 0));
        }

        pub fn getSlot(self: @This()) ?slot.Reader {
            return .{ .reader = self.reader };
        }

        pub fn getGroup(self: @This()) ?group.Reader {
            return .{ .reader = self.reader };
        }

        pub fn getName(self: @This()) capnp.Error![]const u8 {
            return try self.reader.readStringField(0);
        }

        pub fn getCodeOrder(self: @This()) u16 {
            return self.reader.readIntField(u16, 0) ^ 0;
        }

        pub fn getAnnotations(self: @This()) capnp.Error!capnp.CompositeListReader(_Root.Annotation) {
            return try self.reader.readPtrField(capnp.CompositeListReader(_Root.Annotation), 1);
        }

        pub fn getDiscriminantValue(self: @This()) u16 {
            return self.reader.readIntField(u16, 1) ^ 65535;
        }

        pub fn getOrdinal(self: @This()) _Root.Field.ordinal.Reader {
            return .{ .reader = self.reader };
        }
    };
};

pub const Enumerant = struct {
    const id: u64 = 0x978a7cebdc549a4d;

    pub const _Group = struct {};

    pub const Reader = struct {
        reader: capnp.StructReader,

        pub fn getName(self: @This()) capnp.Error![]const u8 {
            return try self.reader.readStringField(0);
        }

        pub fn getCodeOrder(self: @This()) u16 {
            return self.reader.readIntField(u16, 0) ^ 0;
        }

        pub fn getAnnotations(self: @This()) capnp.Error!capnp.CompositeListReader(_Root.Annotation) {
            return try self.reader.readPtrField(capnp.CompositeListReader(_Root.Annotation), 1);
        }
    };
};

pub const Superclass = struct {
    const id: u64 = 0xa9962a9ed0a4d7f8;

    pub const _Group = struct {};

    pub const Reader = struct {
        reader: capnp.StructReader,

        pub fn getId(self: @This()) u64 {
            return self.reader.readIntField(u64, 0) ^ 0;
        }

        pub fn getBrand(self: @This()) capnp.Error!_Root.Brand.Reader {
            return .{ .reader = try self.reader.readPtrField(capnp.StructReader, 0) };
        }
    };
};

pub const Method = struct {
    const id: u64 = 0x9500cce23b334d80;

    pub const _Group = struct {};

    pub const Reader = struct {
        reader: capnp.StructReader,

        pub fn getName(self: @This()) capnp.Error![]const u8 {
            return try self.reader.readStringField(0);
        }

        pub fn getCodeOrder(self: @This()) u16 {
            return self.reader.readIntField(u16, 0) ^ 0;
        }

        pub fn getParamStructType(self: @This()) u64 {
            return self.reader.readIntField(u64, 1) ^ 0;
        }

        pub fn getResultStructType(self: @This()) u64 {
            return self.reader.readIntField(u64, 2) ^ 0;
        }

        pub fn getAnnotations(self: @This()) capnp.Error!capnp.CompositeListReader(_Root.Annotation) {
            return try self.reader.readPtrField(capnp.CompositeListReader(_Root.Annotation), 1);
        }

        pub fn getParamBrand(self: @This()) capnp.Error!_Root.Brand.Reader {
            return .{ .reader = try self.reader.readPtrField(capnp.StructReader, 2) };
        }

        pub fn getResultBrand(self: @This()) capnp.Error!_Root.Brand.Reader {
            return .{ .reader = try self.reader.readPtrField(capnp.StructReader, 3) };
        }

        pub fn getImplicitParameters(self: @This()) capnp.Error!capnp.CompositeListReader(_Root.Node.Parameter) {
            return try self.reader.readPtrField(capnp.CompositeListReader(_Root.Node.Parameter), 4);
        }
    };
};

pub const Type = struct {
    const id: u64 = 0xd07378ede1f9cc60;

    pub const List = struct {
        const id: u64 = 0x87e739250a60ea97;

        pub const Reader = struct {
            reader: capnp.StructReader,

            pub fn getElementType(self: @This()) capnp.Error!_Root.Type.Reader {
                return .{ .reader = try self.reader.readPtrField(capnp.StructReader, 0) };
            }
        };
    };

    pub const Enum = struct {
        const id: u64 = 0x9e0e78711a7f87a9;

        pub const Reader = struct {
            reader: capnp.StructReader,

            pub fn getTypeId(self: @This()) u64 {
                return self.reader.readIntField(u64, 1) ^ 0;
            }

            pub fn getBrand(self: @This()) capnp.Error!_Root.Brand.Reader {
                return .{ .reader = try self.reader.readPtrField(capnp.StructReader, 0) };
            }
        };
    };

    pub const Struct = struct {
        const id: u64 = 0xac3a6f60ef4cc6d3;

        pub const _Group = struct {};

        pub const Reader = struct {
            reader: capnp.StructReader,

            pub fn getTypeId(self: @This()) u64 {
                return self.reader.readIntField(u64, 1) ^ 0;
            }

            pub fn getBrand(self: @This()) capnp.Error!_Root.Brand.Reader {
                return .{ .reader = try self.reader.readPtrField(capnp.StructReader, 0) };
            }
        };
    };

    pub const Interface = struct {
        const id: u64 = 0xed8bca69f7fb0cbf;

        pub const _Group = struct {};

        pub const Reader = struct {
            reader: capnp.StructReader,

            pub fn getTypeId(self: @This()) u64 {
                return self.reader.readIntField(u64, 1) ^ 0;
            }

            pub fn getBrand(self: @This()) capnp.Error!_Root.Brand.Reader {
                return .{ .reader = try self.reader.readPtrField(capnp.StructReader, 0) };
            }
        };
    };

    pub const AnyPointer = struct {
        const id: u64 = 0xc2573fe8a23e49f1;

        pub const _Group = struct {
            pub const Unconstrained = struct {
                pub const _Tag = union(enum) {
                    anyKind: void,
                    struct_: void,
                    list: void,
                    capability: void,
                    _: u16,
                };

                const id: u64 = 0x8e3b5f79fe593656;

                pub const _Group = struct {};

                pub const Reader = struct {
                    reader: capnp.StructReader,

                    pub fn which(self: @This()) capnp.Error!_Tag {
                        return switch (self.reader.readIntField(u16, 5)) {
                            0 => _Tag{ .anyKind = void{} },
                            1 => _Tag{ .struct_ = void{} },
                            2 => _Tag{ .list = void{} },
                            3 => _Tag{ .capability = void{} },
                            else => |n| _Tag{ ._ = n },
                        };
                    }
                };
            };

            pub const Parameter = struct {
                const id: u64 = 0x9dd1f724f4614a85;

                pub const _Group = struct {};

                pub const Reader = struct {
                    reader: capnp.StructReader,

                    pub fn getScopeId(self: @This()) u64 {
                        return self.reader.readIntField(u64, 2) ^ 0;
                    }

                    pub fn getParameterIndex(self: @This()) u16 {
                        return self.reader.readIntField(u16, 5) ^ 0;
                    }
                };
            };

            pub const ImplicitMethodParameter = struct {
                const id: u64 = 0xbaefc9120c56e274;

                pub const _Group = struct {};

                pub const Reader = struct {
                    reader: capnp.StructReader,

                    pub fn getParameterIndex(self: @This()) u16 {
                        return self.reader.readIntField(u16, 5) ^ 0;
                    }
                };
            };
        };

        pub const Reader = struct {
            reader: capnp.StructReader,

            pub const _Tag = union(enum) {
                unconstrained: _Root.Type._Group.AnyPointer._Group.Unconstrained.Reader,
                parameter: _Root.Type._Group.AnyPointer._Group.Parameter.Reader,
                implicitMethodParameter: _Root.Type._Group.AnyPointer._Group.ImplicitMethodParameter.Reader,
                _: u16,
            };

            pub fn which(self: @This()) capnp.Error!_Tag {
                return switch (self.reader.readIntField(u16, 4)) {
                    0 => _Tag{ .unconstrained = .{ .reader = self.reader } },
                    1 => _Tag{ .parameter = .{ .reader = self.reader } },
                    2 => _Tag{ .implicitMethodParameter = .{ .reader = self.reader } },
                    else => |n| _Tag{ ._ = n },
                };
            }
        };
    };

    pub const Tag = enum(u16) {
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
        list,
        enum_,
        struct_,
        interface,
        anyPointer,
    };

    pub const Reader = struct {
        reader: capnp.StructReader,

        pub fn which(self: @This()) Tag {
            return @enumFromInt(self.reader.readIntField(u16, 0));
        }

        pub fn getList(self: @This()) ?Type.List.Reader {
            return if (self.which() == Tag.list) .{ .reader = self.reader } else null;
        }

        pub fn getStruct(self: @This()) ?Type.Struct.Reader {
            return if (self.which() == Tag.struct_) .{ .reader = self.reader } else null;
        }

        pub fn getEnum(self: @This()) ?Type.Struct.Reader {
            return if (self.which() == Tag.enum_) .{ .reader = self.reader } else null;
        }
    };
};

pub const Brand = struct {
    const id: u64 = 0x903455f06065422b;

    pub const _Group = struct {};

    pub const Scope = struct {
        const id: u64 = 0xabd73485a9636bc9;

        pub const _Group = struct {};

        pub const Reader = struct {
            reader: capnp.StructReader,

            pub const _Tag = union(enum) {
                bind: capnp.CompositeListReader(_Root.Brand.Binding),
                inherit: void,
                _: u16,
            };

            pub fn which(self: @This()) capnp.Error!_Tag {
                return switch (self.reader.readIntField(u16, 4)) {
                    0 => _Tag{ .bind = try self.reader.readPtrField(capnp.CompositeListReader(_Root.Brand.Binding), 0) },
                    1 => _Tag{ .inherit = void{} },
                    else => |n| _Tag{ ._ = n },
                };
            }
            pub fn getScopeId(self: @This()) u64 {
                return self.reader.readIntField(u64, 0) ^ 0;
            }
        };
    };

    pub const Binding = struct {
        const id: u64 = 0xc863cd16969ee7fc;

        pub const _Group = struct {};

        pub const Reader = struct {
            reader: capnp.StructReader,

            pub const _Tag = union(enum) {
                unbound: void,
                type: _Root.Type.Reader,
                _: u16,
            };

            pub fn which(self: @This()) capnp.Error!_Tag {
                return switch (self.reader.readIntField(u16, 0)) {
                    0 => _Tag{ .unbound = void{} },
                    1 => _Tag{ .type = .{ .reader = try self.reader.readPtrField(capnp.StructReader, 0) } },
                    else => |n| _Tag{ ._ = n },
                };
            }
        };
    };

    pub const Reader = struct {
        reader: capnp.StructReader,

        pub fn getScopes(self: @This()) capnp.Error!capnp.CompositeListReader(_Root.Brand.Scope) {
            return try self.reader.readPtrField(capnp.CompositeListReader(_Root.Brand.Scope), 0);
        }
    };
};

pub const Value = struct {
    const id: u64 = 0xce23dcd2d7b00c9b;

    pub const _Group = struct {};

    pub const Reader = struct {
        reader: capnp.StructReader,

        pub const _Tag = union(enum) {
            void: void,
            bool: bool,
            int8: i8,
            int16: i16,
            int32: i32,
            int64: i64,
            uint8: u8,
            uint16: u16,
            uint32: u32,
            uint64: u64,
            float32: f32,
            float64: f64,
            text: []const u8,
            data: []const u8,
            list: capnp.AnyPointerReader,
            enum_: u16,
            struct_: capnp.AnyPointerReader,
            interface: void,
            anyPointer: capnp.AnyPointerReader,
            _: u16,
        };

        pub fn which(self: @This()) capnp.Error!_Tag {
            return switch (self.reader.readIntField(u16, 0)) {
                0 => _Tag{ .void = void{} },
                1 => _Tag{ .bool = self.reader.readBoolField(16) },
                2 => _Tag{ .int8 = self.reader.readIntField(i8, 2) ^ 0 },
                3 => _Tag{ .int16 = self.reader.readIntField(i16, 1) ^ 0 },
                4 => _Tag{ .int32 = self.reader.readIntField(i32, 1) ^ 0 },
                5 => _Tag{ .int64 = self.reader.readIntField(i64, 1) ^ 0 },
                6 => _Tag{ .uint8 = self.reader.readIntField(u8, 2) ^ 0 },
                7 => _Tag{ .uint16 = self.reader.readIntField(u16, 1) ^ 0 },
                8 => _Tag{ .uint32 = self.reader.readIntField(u32, 1) ^ 0 },
                9 => _Tag{ .uint64 = self.reader.readIntField(u64, 1) ^ 0 },
                10 => _Tag{ .float32 = self.reader.readFloatField(f32, 1) },
                11 => _Tag{ .float64 = self.reader.readFloatField(f64, 1) },
                12 => _Tag{ .text = try self.reader.readStringField(0) },
                13 => _Tag{ .data = try self.reader.readStringField(0) },
                14 => _Tag{ .list = try self.reader.readPtrField(capnp.AnyPointerReader, 0) },
                15 => _Tag{ .enum_ = self.reader.readIntField(u16, 1) ^ 0 },
                16 => _Tag{ .struct_ = try self.reader.readPtrField(capnp.AnyPointerReader, 0) },
                17 => _Tag{ .interface = void{} },
                18 => _Tag{ .anyPointer = try self.reader.readPtrField(capnp.AnyPointerReader, 0) },
                else => |n| _Tag{ ._ = n },
            };
        }
    };
};

pub const Annotation = struct {
    const id: u64 = 0xf1c8950dab257542;

    pub const _Group = struct {};

    pub const Reader = struct {
        reader: capnp.StructReader,

        pub fn getId(self: @This()) u64 {
            return self.reader.readIntField(u64, 0) ^ 0;
        }

        pub fn getValue(self: @This()) capnp.Error!_Root.Value.Reader {
            return .{ .reader = try self.reader.readPtrField(capnp.StructReader, 0) };
        }

        pub fn getBrand(self: @This()) capnp.Error!_Root.Brand.Reader {
            return .{ .reader = try self.reader.readPtrField(capnp.StructReader, 1) };
        }
    };
};

pub const ElementSize = enum {
    empty,
    bit,
    byte,
    twoBytes,
    fourBytes,
    eightBytes,
    pointer,
    inlineComposite,
};
pub const CapnpVersion = struct {
    const id: u64 = 0xd85d305b7d839963;

    pub const _Group = struct {};

    pub const Reader = struct {
        reader: capnp.StructReader,

        pub fn getMajor(self: @This()) u16 {
            return self.reader.readIntField(u16, 0) ^ 0;
        }

        pub fn getMinor(self: @This()) u8 {
            return self.reader.readIntField(u8, 2) ^ 0;
        }

        pub fn getMicro(self: @This()) u8 {
            return self.reader.readIntField(u8, 3) ^ 0;
        }
    };
};

pub const CodeGeneratorRequest = struct {
    const id: u64 = 0xbfc546f6210ad7ce;

    pub const _Group = struct {};

    pub const RequestedFile = struct {
        const id: u64 = 0xcfea0eb02e810062;

        pub const _Group = struct {};

        pub const Import = struct {
            const id: u64 = 0xae504193122357e5;

            pub const _Group = struct {};

            pub const Reader = struct {
                reader: capnp.StructReader,

                pub fn getId(self: @This()) u64 {
                    return self.reader.readIntField(u64, 0) ^ 0;
                }

                pub fn getName(self: @This()) capnp.Error![]const u8 {
                    return try self.reader.readStringField(0);
                }
            };
        };

        pub const Reader = struct {
            reader: capnp.StructReader,

            pub fn getId(self: @This()) u64 {
                return self.reader.readIntField(u64, 0) ^ 0;
            }

            pub fn getFilename(self: @This()) capnp.Error![]const u8 {
                return try self.reader.readStringField(0);
            }

            pub fn getImports(self: @This()) capnp.Error!capnp.CompositeListReader(_Root.CodeGeneratorRequest.RequestedFile.Import) {
                return try self.reader.readPtrField(capnp.CompositeListReader(_Root.CodeGeneratorRequest.RequestedFile.Import), 1);
            }
        };
    };

    pub const Reader = struct {
        reader: capnp.StructReader,

        pub fn getNodes(self: @This()) capnp.Error!capnp.CompositeListReader(_Root.Node) {
            return try self.reader.readPtrField(capnp.CompositeListReader(_Root.Node), 0);
        }

        pub fn getRequestedFiles(self: @This()) capnp.Error!capnp.CompositeListReader(_Root.CodeGeneratorRequest.RequestedFile) {
            return try self.reader.readPtrField(capnp.CompositeListReader(_Root.CodeGeneratorRequest.RequestedFile), 1);
        }

        pub fn getCapnpVersion(self: @This()) capnp.Error!_Root.CapnpVersion.Reader {
            return .{ .reader = try self.reader.readPtrField(capnp.StructReader, 2) };
        }

        pub fn getSourceInfo(self: @This()) capnp.Error!capnp.CompositeListReader(_Root.Node.SourceInfo) {
            return try self.reader.readPtrField(capnp.CompositeListReader(_Root.Node.SourceInfo), 3);
        }
    };
};

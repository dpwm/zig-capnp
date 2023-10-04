@0xdb8a61f1a2e0afa2;

using Schema = import "/schema.capnp";

const void :Schema.Type = ();

const field1 :Schema.Field = (
    slot = (
        type = (int32=void),
        offset = 3,
    )
);

const node :Schema.Node = (
    struct = (
    fields = [
        (name="void", slot=(type=(void=void))),
        (name="bool", slot=(type=(bool=void))),
        (name="int32", slot=(type=(int32=void), offset=0)),
        (name="float32", slot=(type=(float32=void))),
        (name="text", slot=(type=(text=void))),
        (name="data", slot=(type=(data=void))),
        (name="int32List", slot=(type=(list=(elementType=(int32=void))))),
        (name="struct", slot=(type=(struct=(typeId=0x0)))),
    ],
    ),
);
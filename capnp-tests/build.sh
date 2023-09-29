capnp eval -b 01_simple_struct.capnp date20230714 > 01_simple_struct_date_20230714.bin
capnp eval -b 01_simple_struct.capnp datem20230714  > 01_simple_struct_datem_20230714.bin
capnp eval -b 02_simple_lists.capnp listTest > 02_simple_lists.bin
capnp eval -b 03_composite_lists.capnp listTest > 03_composite_lists.bin
capnp eval -b 04_unions.capnp test1 > 04_unions.bin
capnp eval -b 05_default_values.capnp test > 05_default_values.bin
capnp eval -b 07_bits_and_floats.capnp test > 07_bits_and_floats.bin

capnp compile -o - /usr/include/capnp/schema.capnp > 06_schema.capnp.original.bin
capnp convert binary:binary --segment-size=8000000 < 06_schema.capnp.original.bin > 06_schema.capnp.original.1.bin

capnp eval -I/usr/include/capnp -b 08-schema-examples.capnp void > 08-schema-examples.void.bin
capnp eval -I/usr/include/capnp -b 08-schema-examples.capnp field1 > 08-schema-examples.field1.bin
capnp eval -I/usr/include/capnp -b 08-schema-examples.capnp node > 08-schema-examples.node.bin


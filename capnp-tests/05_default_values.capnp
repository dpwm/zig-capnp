@0x9064d9389017a737;

struct Defaults {
	int32 @0 :Int32 = 17;
	struct @1 :Defaults = (int32 = 15);
}

const test :Defaults = (int32 = 17);

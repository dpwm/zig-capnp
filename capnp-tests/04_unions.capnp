@0xd0cb1cebd8e358cb;

struct UnionTest {
    union {
        void @0 :Void;
        int32 @1 :Int32;
    }
}

struct UnionTestList {
    unionTests @0 :List(UnionTest);
}

const test1:UnionTestList = (unionTests = [(int32=0), (void=void), (int32=2)]);
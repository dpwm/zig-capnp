@0xd53869d44613edfc;

struct Date {
    year @0 :Int16;
    month @1 :UInt8;
    day @2 :UInt8;
}

struct Lists {
    dates @0 :List(Date);
}

const listTest :Lists = (
    dates = [(year=2023,month=7,day=14), (year=2022, month=7, day=14)]
);


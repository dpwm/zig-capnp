@0xa85b693adf357ded;

struct Date {
    year @0 :Int16;
    month @1 :UInt8;
    day @2 :UInt8;
}

const date20230714 :Date = (
    year = 2023,
    month = 7,
    day = 14,
    );

const datem20230714 :Date = (
    year = -2023,
    month = 7,
    day = 14,
    );
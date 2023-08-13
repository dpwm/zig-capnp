@0xb2876a57053fb0f7;

struct Test {
    float32 @0 :Float32;
    float64 @1 :Float64;
    bit @2 :Bool;
}

const test : Test = (float32=3.141, float64=3.14159, bit = true);
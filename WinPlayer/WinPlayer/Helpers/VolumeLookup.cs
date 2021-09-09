using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace WinPlayer
{
    public static class VolumeLookup
    {
        public static int Lookup(int volume) => volume switch
        {
            0 => 0,
            1 => 1,
            2 => 1,
            3 => 1,
            4 => 2,
            5 => 2,
            6 => 2,
            7 => 2,
            8 => 2,
            9 => 2,
            10 => 2,
            11 => 3,
            12 => 3,
            13 => 3,
            14 => 3,
            15 => 3,
            16 => 4,
            17 => 4,
            18 => 4,
            19 => 4,
            20 => 5,
            21 => 5,
            22 => 5,
            23 => 6,
            24 => 6,
            25 => 7,
            26 => 7,
            27 => 7,
            28 => 8,
            29 => 8,
            30 => 9,
            31 => 9,
            32 => 10,
            33 => 11,
            34 => 11,
            35 => 12,
            36 => 13,
            37 => 14,
            38 => 14,
            39 => 15,
            40 => 16,
            41 => 17,
            42 => 18,
            43 => 19,
            44 => 21,
            45 => 22,
            46 => 23,
            47 => 25,
            48 => 26,
            49 => 28,
            50 => 29,
            51 => 31,
            52 => 33,
            53 => 35,
            54 => 37,
            55 => 39,
            56 => 42,
            57 => 44,
            58 => 47,
            59 => 50,
            60 => 52,
            61 => 56,
            62 => 59,
            63 => 63,
            _ => throw new Exception("Unknown level")
        };
    }
}

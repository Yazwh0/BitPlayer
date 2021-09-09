using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Newtonsoft.Json;

namespace WinPlayer.Models
{
    public class Pattern
    {
        public int Number { get; set; }
        public string Name { get; set; } = "";
        public int Speed { get; set; }
        public int TrackLength { get; set; } = 64;

        [JsonIgnore]
        public string DisplayName => $"{Number:X2} {Name}";

        public List<Track> Tracks { get; set; } = new List<Track>();

        public Pattern()
        {
        }
    }
}

using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using WinPlayer.Command;

namespace WinPlayer.Models
{
    public class Note
    {
        public int Position { get; set; }
        public int NoteNum { get; set; }
        public int InstrumentNumber { get; set; }
        public Commands Command { get; set; }
        public short CommandParam { get; set; }

        [JsonIgnore]
        public string PositionStr
        {
            get
            {
                return Position.ToString("X2");
            }
        }

        [JsonIgnore]
        public string NoteStr
        {
            get
            {
                if (NoteNum == 0)
                    return "";

                if (NoteNum == 1)
                    return "---";

                var octave = (int)(NoteNum / 12.0);
                return "C-C#D-D#E-F-F#G-G#A-A#B-".Substring(NoteNum % 12 * 2, 2) + $"{octave}";
            }
        }

        [JsonIgnore]
        public string CommandStr => CommandFactory.GetDisplay(Command);

        [JsonIgnore]
        public string CommandParamStr
        {
            get
            {
                if (Command == Commands.None)
                    return "";

                return CommandParam.ToString("X4");
            }
        }

        [JsonIgnore]
        public string InstrumentStr
        {
            get
            {
                if (NoteNum == 0)
                    return "";

                return InstrumentNumber.ToString("X2");
            }
            set
            {
                InstrumentNumber = Convert.ToInt32(value, 16);
            }
        }

        public Note Clone() => new Note()
        {
            Position = Position,
            Command = Command,
            CommandParam = CommandParam,
            NoteNum = NoteNum,
            InstrumentNumber = InstrumentNumber
        };
    }
}

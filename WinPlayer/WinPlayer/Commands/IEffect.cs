using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace WinPlayer.Command
{
    public interface ICommand
    {
        public short Parameters { get; set; }
        public byte Parameters1 => (byte)(Parameters & 255);
        public byte Parameters2 => (byte)(Parameters >> 80);

        public void ApplyNext(Waveform.IVeraWaveform generator);
        public void Remove(Waveform.IVeraWaveform generator);
    }

    public enum Commands
    {
        None,
        Warble,
        FrequencyDown,
        FrequencyUp,
        ClearCommand,
    }

    public static class CommandFactory
    {
        public static ICommand GetCommand(Commands effect, short parameter)
        {
            ICommand toReturn = effect switch
            {
                Commands.FrequencyDown => new FrequencyDown(),
                Commands.FrequencyUp => new FrequencyUp(),
                Commands.Warble => new Warble(),
                Commands.ClearCommand => new NoEffect(),
                _ => new NoEffect()
            };

            toReturn.Parameters = parameter;
            return toReturn;
        }
    }
}

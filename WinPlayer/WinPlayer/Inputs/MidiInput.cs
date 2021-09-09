using NAudio.Midi;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace WinPlayer
{
    public interface IInputSource
    {
        public event EventHandler<InputEvent> PlayNote;
    }

    public class MidiSource : IInputSource
    {
        private MidiIn _midiIn;

        public event EventHandler<InputEvent> PlayNote;

        public MidiSource(MidiIn midiIn)
        {
            _midiIn = midiIn;
            _midiIn.MessageReceived += _midiIn_MessageReceived;
        }

        private void _midiIn_MessageReceived(object sender, MidiInMessageEventArgs e)
        {
            if (e.MidiEvent.CommandCode == MidiCommandCode.NoteOn)
            {
                var midiEvent = (NoteOnEvent)e.MidiEvent;
                Debug.WriteLine($"{midiEvent.NoteNumber}: {midiEvent.NoteName}");

                PlayNote?.Invoke(this, new InputEvent { NoteNumber = midiEvent.NoteNumber });
            }
        }
    }

    public class InputEvent
    {
        public int NoteNumber { get; set; }
    }
}

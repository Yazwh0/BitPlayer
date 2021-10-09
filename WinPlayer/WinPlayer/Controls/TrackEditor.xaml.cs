using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Navigation;
using System.Windows.Shapes;

namespace WinPlayer.Controls
{
    public class TrackEditorNoteChangedEventArgs : EventArgs
    {
        public TrackEditorNoteChangedEventArgs(Models.Note note)
        {
            Note = note;
        }

        public Models.Note Note { get; set; }
    }

    /// <summary>
    /// Interaction logic for TrackEditor.xaml
    /// </summary>
    public partial class TrackEditor : UserControl
    {
        private Models.Track? _value;
        private bool _editing = false;
      //  private Models.Note[]? _value = null;

        public event EventHandler<TrackEditorNoteChangedEventArgs>? NoteChanged = null;

        private bool _fireEvents = true;

        public Models.Track? Value
        {
            get => _value; 
            set
            {
                Notes.ItemsSource = null;
                Notes.ItemsSource = value.Notes;
                _value = value;
            }
        }

        public TrackEditor()
        {
            InitializeComponent();
            Notes.PreviewKeyDown += Notes_KeyDown;
        }

        private void Notes_KeyDown(object sender, KeyEventArgs e)
        {
            if (_editing)
                return;

            if (e.Key == Key.Delete || e.Key == Key.Back) 
            {
/*                var note = (Models.Note)Notes.SelectedItem;
                note.NoteNum = 0;
                note.Command = Command.Commands.None;
                note.CommandParam = 0;*/
                NoteChange(new Models.Note());
                e.Handled = true;
                Notes.ScrollIntoView(Notes.Items[Notes.SelectedIndex]);
                return;
            }

            if (e.Key == Key.Down)
            {
                _fireEvents = false;
                var i = Notes.SelectedIndex;
                if (i < _value.Notes.Length) i++;
                Notes.SelectedIndex = i;
                e.Handled = true;
                _fireEvents = true;
                Notes.ScrollIntoView(Notes.Items[Notes.SelectedIndex]);
                return;
            }

            if (e.Key == Key.Up)
            {
                _fireEvents = false;
                var i = Notes.SelectedIndex;
                if (i > 0) i--;
                Notes.SelectedIndex = i;
                e.Handled = true;
                _fireEvents = true;
                Notes.ScrollIntoView(Notes.Items[Notes.SelectedIndex]);
                return;
            }

            if (e.Key == Key.I)
            {
                _fireEvents = false;
                var i = Notes.SelectedIndex;
                
                if (_value == null) throw new Exception();

                var temp = _value.Notes.ToList();

                temp.Insert(i, new Models.Note());
                temp.RemoveAt(temp.Count-1);

                for(var j = 0; j < _value.Notes.Length; j++)
                {
                    _value.Notes[j] = temp[j];
                    _value.Notes[j].Position = j;
                }
                Notes.Items.Refresh();
                e.Handled = true;
                _fireEvents = true;
                return;
            }

            if (e.Key == Key.D)
            {
                _fireEvents = false;
                var i = Notes.SelectedIndex;

                if (_value == null) throw new Exception();

                var temp = _value.Notes.ToList();

                temp.RemoveAt(i);
                temp.Add(new Models.Note());

                for (var j = 0; j < _value.Notes.Length; j++)
                {
                    _value.Notes[j] = temp[j];
                    _value.Notes[j].Position = j;
                }

                Notes.Items.Refresh();
                e.Handled = true;
                _fireEvents = true;
                return;
            }

            if (e.Key == Key.Escape)
            {
                if (Globals.WaveOut != null)
                {
                    Globals.WaveOut.Stop();
                    Globals.WaveOut = null;
                }
            }

            if (e.Key == Key.S)
            {
                var i = Notes.SelectedIndex;
                var note = _value.Notes[i].Clone();
                note.NoteNum = 1;
                NoteChange(note);

                Notes.Items.Refresh();
                e.Handled = true;
                _fireEvents = true;
                return;
            }
        }

        private void Notes_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (e.AddedItems.Count == 0)
                return;
            
            var item = e.AddedItems[0] as Models.Note;

            if (item == null)
                return;

            var args = new TrackEditorNoteChangedEventArgs(item);

            var shiftPressed = Keyboard.GetKeyStates(Key.LeftShift) == KeyStates.Down || Keyboard.GetKeyStates(Key.RightShift) == KeyStates.Down;

            if (NoteChanged != null && _fireEvents && shiftPressed)
                NoteChanged.Invoke(this, args);
        }

        public void NoteChange(Models.Note note)
        {
            if (_editing)
                return;

            if (_value == null)
                throw new Exception();

            _fireEvents = false;
            var i = Notes.SelectedIndex;
            _value.Notes[i] = note.Clone();
            _value.Notes[i].Position = i;

            Notes.Items.Refresh();
          
            if (i < _value.Notes.Length-1) i++;

            Notes.SelectedIndex = i;

            Notes.UpdateLayout();
            Notes.ScrollIntoView(Notes.Items[i]);
            Notes.Focus();
            _fireEvents = true;
        }

        public void Refresh()
        {
            Notes.ItemsSource = null;
            Notes.ItemsSource = Value.Notes;
        }

        private void Notes_BeginningEdit(object sender, DataGridBeginningEditEventArgs e)
        {
            _editing = true;
        }

        private void Notes_CellEditEnding(object sender, DataGridCellEditEndingEventArgs e)
        {
            _editing = false;
        }

        private void Notes_MouseDoubleClick(object sender, MouseButtonEventArgs e)
        {
            var item = Notes.SelectedItem as Models.Note;

            if (item == null)
                return;

            var args = new TrackEditorNoteChangedEventArgs(item);

            NoteChanged?.Invoke(this, args);
        }
    }
}

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
        private Models.Note[]? _value = null;

        public event EventHandler<TrackEditorNoteChangedEventArgs>? NoteChanged = null;

        private bool _fireEvents = true;


        public Models.Note[]? Value
        {
            get => _value; 
            set
            {
                Notes.ItemsSource = null;
                Notes.ItemsSource = value;
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
                if (i < _value.Length) i++;
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

                var temp = _value.ToList();

                temp.Insert(i, new Models.Note());
                temp.RemoveAt(64);

                for(var j = 0; j < _value.Length; j++)
                {
                    _value[j] = temp[j];
                    _value[j].Position = j;
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

                var temp = _value.ToList();

                temp.RemoveAt(i);
                temp.Add(new Models.Note());

                for (var j = 0; j < _value.Length; j++)
                {
                    _value[j] = temp[j];
                    _value[j].Position = j;
                }

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
            if (_value == null)
                throw new Exception();

            _fireEvents = false;
            var i = Notes.SelectedIndex;
            _value[i] = note.Clone();
            _value[i].Position = i;
            Notes.Items.Refresh();
          
            if (i < _value.Length-1) i++;

            Notes.SelectedIndex = i;

            Notes.UpdateLayout();
            Notes.ScrollIntoView(Notes.Items[i]);
            Notes.Focus();
            _fireEvents = true;
        }
    }
}

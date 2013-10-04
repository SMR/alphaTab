package alphatab.importer;
import alphatab.model.AccentuationType;
import alphatab.model.Automation;
import alphatab.model.AutomationType;
import alphatab.model.Bar;
import alphatab.model.Beat;
import alphatab.model.BendPoint;
import alphatab.model.BrushType;
import alphatab.model.Chord;
import alphatab.model.Clef;
import alphatab.model.Duration;
import alphatab.model.DynamicValue;
import alphatab.model.GraceType;
import alphatab.model.HarmonicType;
import alphatab.model.MasterBar;
import alphatab.model.Note;
import alphatab.model.Score;
import alphatab.model.Section;
import alphatab.model.SlideType;
import alphatab.model.Track;
import alphatab.model.TripletFeel;
import alphatab.model.VibratoType;
import alphatab.model.Voice;
import haxe.ds.IntMap.IntMap;
import haxe.ds.StringMap.StringMap;
import haxe.xml.Fast;

class GpxRhythm
{    
    public var dots:Int;
    public var tupletDenominator:Int;
    public var tupletNumerator:Int;
    public var value:Duration;
    
    public function new()
    {
        tupletNumerator = 1;
        tupletDenominator = 1;
        value = Duration.Quarter;
    }
}

/**
 * This class can parse a score.gpif xml file into the model structure
 */
class GpxParser 
{
    private static inline var InvalidId = "-1";

	public var score:Score;
    private var _automations:StringMap<Array<Automation>>;
    private var _tracksMapping:Array<String>;
    private var _tracksById:StringMap<Track>; // contains tracks by their id
    
    private var _masterBars:Array<MasterBar>; // contains all masterbars in correct order
    private var _barsOfMasterBar:Array<Array<String>>; // contains ids of bars placed at this masterbar over all tracks (sequencially)
    
    private var _barsById:StringMap<Bar>; // contains bars by their id
    private var _voicesOfBar:StringMap<Array<String>>; // contains ids of voices stored in a bar (key = bar id)
    
    private var _voiceById:StringMap<Voice>; // contains voices by their id
    private var _beatsOfVoice:StringMap<Array<String>>; // contains ids of beats stored in a voice (key = voice id) 

    private var _rhythmOfBeat:StringMap<String>; // contains ids of rhythm used by a beat (key = beat id)
    private var _beatById:StringMap<Beat>; // contains beats by their id

    private var _rhythmById:StringMap<GpxRhythm>; // contains rhythms by their id

    private var _noteById:StringMap<Note>; // contains notes by their id
    private var _notesOfBeat:StringMap<Array<String>>; // contains ids of notes stored in a beat (key = beat id);
    
	public function new() 
	{
		
	}
	
	public function parseXml(xml:String)
	{
        _automations = new StringMap<Array<Automation>>();
        _tracksMapping = new Array<String>();
        _tracksById = new StringMap<Track>(); 
        _masterBars = new Array<MasterBar>(); 
        _barsOfMasterBar = new Array<Array<String>>(); 
        _voicesOfBar = new StringMap<Array<String>>(); 
        _barsById = new StringMap<Bar>(); 
        _voiceById = new StringMap<Voice>();
        _beatsOfVoice = new StringMap<Array<String>>();
        _beatById = new StringMap<Beat>(); 
        _rhythmOfBeat = new StringMap<String>();
        _rhythmById = new StringMap<GpxRhythm>(); 
        _notesOfBeat = new StringMap<Array<String>>(); 
        _noteById = new StringMap<Note>(); 

		var dom = Xml.parse(xml);
		parseDom(dom);		
	}
	
	public function parseDom(xml:Xml)
	{
        if (xml.nodeType == Xml.Document)
        {
            xml = xml.firstElement();
        }
        
        
		// the XML uses IDs for referring elements within the 
		// model. Therefore we do the parsing in 2 steps:
		// - at first we read all model elements and store them by ID in a lookup table
		// - after that we need to join up the information. 
		if (xml.nodeName == "GPIF")
		{
			score = new Score();
			
			// parse all children
			for (n in xml)
			{
                if (n.nodeType == Xml.Element)
                {
                    switch(n.nodeName)
                    {
                        case "Score":
                            parseScoreNode(n);
                        case "MasterTrack":
                        	parseMasterTrackNode(n);
                        case "Tracks":
                        	parseTracksNode(n);
                        case "MasterBars":
                        	parseMasterBarsNode(n);
                        case "Bars":
                        	parseBars(n);
                        case "Voices":
                        	parseVoices(n);
                        case "Beats":
                        	parseBeats(n);
                        case "Notes":
                        	parseNotes(n);
                        case "Rhythms":
                        	parseRhythms(n);
                    }
                }
			}
		}
		else
		{
			throw ScoreImporter.UNSUPPORTED_FORMAT;
		}
            
        buildModel();
	}
    
    private function getValue(n:Xml) : String
    {
        if (n.nodeType == Xml.Element || n.nodeType == Xml.Document)
        {
            var txt = new StringBuf();
            for (c in n)
            {
                txt.add(getValue(c));
            }
            return StringTools.trim(txt.toString());
        }
        else
        {
            return n.nodeValue;
        }
    }
   
    private function findChildElement(node:Xml, name:String)
    {
        for (c in node)
        {
            if (c.nodeType == Xml.Element)
            {           
                if (c.nodeName == name) return c;
            }
        }
        return null;
    }
	
    //
    // <Score>...</Score>
    // 
    
	private function parseScoreNode(node:Xml)
	{
		for (c in node)
		{
            if (c.nodeType == Xml.Element)
            {
                switch(c.nodeName)
                {
                    case "Title": score.title = getValue(c.firstChild());
                    case "SubTitle": score.subTitle = getValue(c.firstChild());
                    case "Artist": score.artist = getValue(c.firstChild());
                    case "Album": score.album = getValue(c.firstChild());
                    case "Words": score.words = getValue(c.firstChild());
                    case "Music": score.music = getValue(c.firstChild());
                    case "WordsAndMusic": if (c.firstChild() != null && c.firstChild().toString() != "") { score.words = getValue(c.firstChild()); score.music = getValue(c.firstChild()); } 
                    case "Copyright": score.copyright = getValue(c.firstChild());
                    case "Tabber": score.tab = getValue(c.firstChild());
                }
            }
		}
	}
    	
    //
    // <MasterTrack>...</MasterTrack>
    //  
    
    private function parseMasterTrackNode(node:Xml)
    {
		for (c in node)
		{
            if (c.nodeType == Xml.Element)
            {      
                switch(c.nodeName)
                {
                    case "Automations":
                        parseAutomations(c);
                    case "Tracks":
                        _tracksMapping = getValue(c).split(" ");
                }
            }
		}
    }
    
    private function parseAutomations(node:Xml)
    {
        for (c in node)
		{
            if (c.nodeType == Xml.Element)
            {           
                switch(c.nodeName)
                {
                    case "Automation": parseAutomation(c);
                }
            }
		}
    }
    
    private function parseAutomation(node:Xml)
    {
        var type:String = null;
        var isLinear:Bool = false;
        var barId:String = null;
        var ratioPosition:Float = 0;
        var value:Float = 0;
        var reference:Int = 0;
        var text:String = null;
        
        for (c in node)
		{
            if (c.nodeType == Xml.Element)
            {               
                switch(c.nodeName)
                {
                    case "Type": type = getValue(c);
                    case "Linear": isLinear = getValue(c).toLowerCase() == "true";
                    case "Bar": barId = getValue(c);
                    case "Position": ratioPosition = Std.parseFloat(getValue(c));
                    case "Value":
                        var parts = getValue(c).split(" ");
                        value = Std.parseFloat(parts[0]);
                        reference = Std.parseInt(parts[1]);
                    case "Text": text = getValue(c);
                }
            }
		}
        
        if (type == null) return;
        var automation:Automation = null;
        switch(type)
        {
            case "Tempo":
                automation = Automation.builtTempoAutomation(isLinear, ratioPosition, value, reference);
            // TODO: other automations
        }
        automation.text = text;
        
        if (automation != null)
        {
            if (!_automations.exists(barId)) _automations.set(barId, new Array<Automation>());
            _automations.get(barId).push(automation);
        }
    }
   
    	
    //
    // <Tracks>...</Tracks>
    //  
        
    private function parseTracksNode(node:Xml)
    {
        for (c in node)
		{
            if (c.nodeType == Xml.Element)
            {           
                switch(c.nodeName)
                {
                    case "Track": parseTrack(c);
                }
            }
		}
    }
    
    private function parseTrack(node:Xml)
    {
        var track = new Track();
        var trackId:String = node.get("id");
        
        for (c in node)
		{
            if (c.nodeType == Xml.Element)
            {           
                switch(c.nodeName)
                {
                    case "Name": track.name = getValue(c);
                    case "ShortName": track.shortName = getValue(c);
                    //TODO: case "Lyrics": parseLyrics(track, c);
                    case "Properties": parseTrackProperties(track, c);
                    case "DiagramCollection": parseDiagramCollection(track, c);
                    case "GeneralMidi": parseGeneralMidi(track, c);
                    case "PlaybackState": 
                        var state = getValue(c);
                        track.playbackInfo.isSolo = state == "Solo";
                        track.playbackInfo.isMute = state == "Mute";
                }
            }
		}
        _tracksById.set(trackId, track);
    }
    
    private function parseDiagramCollection(track:Track, node:Xml)
    {
        var items = findChildElement(node, "Items");
        for (c in items)
		{
            if (c.nodeType == Xml.Element)
            {           
                switch(c.nodeName)
                {
                    case "Item": parseDiagramItem(track, c);
                }
            }
		}
    }
    
    private function parseDiagramItem(track:Track, node:Xml)
    {
        var chord = new Chord();
        var chordId = node.get("id");
        chord.name = node.get("name");
        track.chords.set(chordId, chord);
    }
    
    private function parseTrackProperties(track:Track, node:Xml)
    {
        for (c in node)
		{
            if (c.nodeType == Xml.Element)
            {           
                switch(c.nodeName)
                {
                    case "Property": parseTrackProperty(track, c);
                }
            }
		}
    }
    
    private function parseTrackProperty(track:Track, node:Xml)
    {
        var propertyName = node.get("name");
        switch(propertyName)
        {
            case "Tuning": 
                var tuningParts = getValue(findChildElement(node, "Pitches")).split(" ");
                for (s in tuningParts) track.tuning.push(Std.parseInt(s));
                track.tuning.reverse();
            case "CapoFret":
                track.capo = Std.parseInt(getValue(findChildElement(node, "Fret")));
        }
    }
    
    private function parseGeneralMidi(track:Track, node:Xml)
    {
        track.playbackInfo.port = Std.parseInt(getValue(findChildElement(node, "Port")));
        track.playbackInfo.program = Std.parseInt(getValue(findChildElement(node, "Program")));
        track.playbackInfo.primaryChannel = Std.parseInt(getValue(findChildElement(node, "PrimaryChannel")));
        track.playbackInfo.secondaryChannel = Std.parseInt(getValue(findChildElement(node, "SecondaryChannel")));

        track.isPercussion = (node.get("table") == "Percussion");
    }
    	
    //
    // <MasterBars>...</MasterBars>
    //  
    
    private function parseMasterBarsNode(node:Xml)
    {
        for (c in node)
		{
            if (c.nodeType == Xml.Element)
            {           
                switch(c.nodeName)
                {
                    case "MasterBar": parseMasterBar(c);
                }
            }
		}
    }
   
    private function parseMasterBar(node:Xml)
    {
        var masterBar = new MasterBar();
        for (c in node)
		{
            if (c.nodeType == Xml.Element)
            {           
                switch(c.nodeName)
                {
                    case "Time":
                        var timeParts = getValue(c).split("/");
                        masterBar.timeSignatureNumerator = Std.parseInt(timeParts[0]);
                        masterBar.timeSignatureDenominator = Std.parseInt(timeParts[1]);
                    case "DoubleBar": 
                        masterBar.isDoubleBar = true;
                    case "Section": 
                        masterBar.section = new Section();
                        masterBar.section.marker = getValue(findChildElement(c, "Letter"));
                        masterBar.section.text = getValue(findChildElement(c, "Text"));
                    case "Repeat": 
                        if (c.get("start").toLowerCase() == "true")
                        {
                            masterBar.isRepeatStart = true;
                        }
                        if (c.get("end").toLowerCase() == "true" && c.get("count") != null)
                        {
                            masterBar.repeatCount = Std.parseInt(c.get("count"));
                        }
                        
                    // TODO case "Directions": // Coda segno etc. 
                    case "AlternateEndings":
                        var alternateEndings = getValue(c).split(" ");
                        var i = 0;
                        for (k in 0 ... alternateEndings.length)
                        {
                            i |= 1 << ( -1 + Std.parseInt(alternateEndings[i]));
                        }
                        masterBar.alternateEndings = i;
                    case "Bars": 
                        _barsOfMasterBar.push(getValue(c).split(" "));
                    case "TripletFeel": 
                        switch(getValue(c))
                        {
                            case "NoTripletFeel": masterBar.tripletFeel = TripletFeel.NoTripletFeel;
                            case "Triplet8th": masterBar.tripletFeel = TripletFeel.Triplet8th;
                            case "Triplet16th": masterBar.tripletFeel = TripletFeel.Triplet16th;
                            case "Dotted8th": masterBar.tripletFeel = TripletFeel.Dotted8th;
                            case "Dotted16th": masterBar.tripletFeel = TripletFeel.Dotted16th;
                            case "Scottish8th": masterBar.tripletFeel = TripletFeel.Scottish8th;
                            case "Scottish16th": masterBar.tripletFeel = TripletFeel.Scottish16th;
                        }
                }
            }
		}
        _masterBars.push(masterBar);        
    }
    	
    //
    // <Bars>...</Bars>
    //  

    private function parseBars(node:Xml)
    {
        for (c in node)
		{
            if (c.nodeType == Xml.Element)
            {           
                switch(c.nodeName)
                {
                    case "Bar": parseBar(c);
                }
            }
		}        
    }
    
    private function parseBar(node:Xml)
    {
        var bar = new Bar();
        var barId = node.get("id");
        
        for (c in node)
		{
            if (c.nodeType == Xml.Element)
            {           
                switch(c.nodeName)
                {
                    case "Voices":
                        _voicesOfBar.set(barId, getValue(c).split(" "));
                    case "Clef":
                        switch(getValue(c))
                        {
                            case "Neutral": bar.clef = Clef.Neutral;
                            case "G2": bar.clef = Clef.G2;
                            case "F4": bar.clef = Clef.F4;
                            case "C4": bar.clef = Clef.C4;
                            case "C3": bar.clef = Clef.C3;
                        }
                    // case "SimileMark":
                }
            }
		}
        
        _barsById.set(barId, bar);
    }
    
    //
    // <Voices>...</Voices>
    // 
    
    private function parseVoices(node:Xml)
    {
        for (c in node)
		{
            if (c.nodeType == Xml.Element)
            {           
                switch(c.nodeName)
                {
                    case "Voice": parseVoice(c);
                }
            }
		}        
    }
    
    private function parseVoice(node:Xml)
    {
        var voice = new Voice();
        var voiceId = node.get("id");
        
        for (c in node)
		{
            if (c.nodeType == Xml.Element)
            {           
                switch(c.nodeName)
                {
                    case "Beats":
                        _beatsOfVoice.set(voiceId, getValue(c).split(" "));
                }
            }
		}
        
        _voiceById.set(voiceId, voice);
    }
    
    //
    // <Beats>...</Beats>
    // 
    
    private function parseBeats(node:Xml)
    {
        for (c in node)
		{
            if (c.nodeType == Xml.Element)
            {           
                switch(c.nodeName)
                {
                    case "Beat": parseBeat(c);
                }
            }
		}        
    }
    
    private function parseBeat(node:Xml)
    {
        var beat = new Beat();
        var beatId = node.get("id");
        
        for (c in node)
		{
            if (c.nodeType == Xml.Element)
            {           
                switch(c.nodeName)
                {
                    case "Notes":
                        _notesOfBeat.set(beatId, getValue(c).split(" "));
                    case "Rhythm":
                        _rhythmOfBeat.set(beatId, c.get("ref"));
                    case "Tremolo":
                        switch(getValue(c))
                        {
                            case "1/2": beat.tremoloSpeed = Duration.Half;
                            case "1/4": beat.tremoloSpeed = Duration.Quarter;
                            case "1/8": beat.tremoloSpeed = Duration.Eighth;
                        }
                    case "Chord":
                        beat.chordId = getValue(c);
                    case "Arpreggio":
                        if (getValue(c) == "Up")
                        {
                            beat.brushType = BrushType.ArpeggioUp;
                        }
                        else
                        {
                            beat.brushType = BrushType.ArpeggioDown;
                        }
                        // TODO: brushDuration
                    case "Properties":
                        parseBeatProperties(c, beat);
                    case "FreeText":
                        beat.text = getValue(c);
                    case "Dynamic":
                        switch(getValue(c))
                        {
                            case "PPP": beat.dynamicValue = DynamicValue.PPP;
                            case "PP": beat.dynamicValue = DynamicValue.PP;
                            case "P": beat.dynamicValue = DynamicValue.P;
                            case "MP": beat.dynamicValue = DynamicValue.MP;
                            case "MF": beat.dynamicValue = DynamicValue.MF;
                            case "F": beat.dynamicValue = DynamicValue.F;
                            case "FF": beat.dynamicValue = DynamicValue.FF;
                            case "FFF": beat.dynamicValue = DynamicValue.FFF;
                        }
                    case "GraceNotes":
                        switch(getValue(c))
                        {
                            case "OnBeat": beat.graceType = GraceType.OnBeat;
                            case "BeforeBeat": beat.graceType = GraceType.BeforeBeat;
                        }
                }
            }
		}
        
        _beatById.set(beatId, beat);
    }
    
    private function parseBeatProperties(node:Xml, beat:Beat)
    {
        for (c in node)
		{
            if (c.nodeType == Xml.Element)
            {           
                switch(c.nodeName)
                {
                    case "Property":
                        parseBeatProperty(c, beat);
                }
            }
		}
    }
    
    private function parseBeatProperty(node:Xml, beat:Beat)
    {
        var isWhammyBar :Bool = false;
        var whammyBarOrigin:BendPoint = null;
        var whammyBarMiddle1:BendPoint = null;
        var whammyBarMiddle2:BendPoint = null;
        var whammyBarDestination:BendPoint = null;
        
        var name = node.get("name");
        switch(name)
        {
            case "Brush": 
                if (getValue(findChildElement(node, "Direction")) == "Up")
                {
                    beat.brushType = BrushType.BrushUp;
                }
                else
                {
                    beat.brushType = BrushType.BrushDown;
                }
                // TODO: brush duration
            case "Slapped":if (findChildElement(node, "Enable") != null) beat.slap = true;
            case "Popped": if (findChildElement(node, "Enable") != null) beat.pop = true;
            // TODO: correct whammy bar values and offsets
            case "WhammyBar": isWhammyBar = true;
            case "WhammyBarExtend":
            
            case "WhammyBarOriginValue": 
                if (whammyBarOrigin == null) whammyBarOrigin = new BendPoint();
                whammyBarOrigin.value = Std.int(Std.parseFloat(getValue(findChildElement(node, "Float"))));
            case "WhammyBarOriginOffset":
                if (whammyBarOrigin == null) whammyBarOrigin = new BendPoint();
                whammyBarOrigin.offset = Std.int(Std.parseFloat(getValue(findChildElement(node, "Float"))));

            case "WhammyBarMiddleValue":
                if (whammyBarMiddle1 == null) whammyBarMiddle1 = new BendPoint();
                if (whammyBarMiddle2 == null) whammyBarMiddle2 = new BendPoint();
                whammyBarMiddle1.value = Std.int(Std.parseFloat(getValue(findChildElement(node, "Float"))));
                whammyBarMiddle2.value = whammyBarMiddle1.value;

            case "WhammyBarMiddleOffset1":
                if (whammyBarMiddle1 == null) whammyBarMiddle1 = new BendPoint();
                whammyBarMiddle1.offset = Std.int(Std.parseFloat(getValue(findChildElement(node, "Float"))));
            case "WhammyBarMiddleOffset2":
                if (whammyBarMiddle2 == null) whammyBarMiddle2 = new BendPoint();
                whammyBarMiddle2.offset = Std.int(Std.parseFloat(getValue(findChildElement(node, "Float"))));
            
            case "WhammyBarDestinationValue":
                if (whammyBarDestination == null) whammyBarDestination = new BendPoint();
                whammyBarDestination.value = Std.int(Std.parseFloat(getValue(findChildElement(node, "Float"))));

            case "WhammyBarDestinationOffset":
                if (whammyBarDestination == null) whammyBarDestination = new BendPoint();
                whammyBarDestination.offset = Std.int(Std.parseFloat(getValue(findChildElement(node, "Float"))));
        }
        
        if (isWhammyBar && whammyBarOrigin != null && whammyBarDestination != null)
        {
            var whammy = new Array<BendPoint>();
            whammy.push(whammyBarOrigin);
            if (whammyBarMiddle1 != null) whammy.push(whammyBarMiddle1);
            if (whammyBarMiddle2 != null) whammy.push(whammyBarMiddle2);
            whammy.push(whammyBarDestination);
            beat.whammyBarPoints = whammy;
        }
    }
    
    //
    // <Notes>...</Notes>
    // 
    
    private function parseNotes(node:Xml)
    {
        for (c in node)
		{
            if (c.nodeType == Xml.Element)
            {           
                switch(c.nodeName)
                {
                    case "Note": parseNote(c);
                }
            }
		}        
    }
    
    private function parseNote(node:Xml)
    {
        var note = new Note();
        var noteId = node.get("id");
        
        for (c in node)
		{
            if (c.nodeType == Xml.Element)
            {           
                switch(c.nodeName)
                {
                    case "Properties":
                        parseNoteProperties(c, note);
                    case "AntiAccent":
                        if (getValue(c).toLowerCase() == "normal")
                        {
                            note.isGhost = true;
                        }
                    case "LetRing":
                        note.isLetRing = true;
                    case "Trill":
                        note.trillFret = Std.parseInt(getValue(c));
                        note.trillSpeed = 1;
                    case "Accent":
                        var accentFlags = Std.parseInt(getValue(c));
                        if ( (accentFlags & 0x01) != 0) note.isStaccato = true;
                        if ( (accentFlags & 0x04) != 0) note.accentuated = AccentuationType.Heavy;
                        if ( (accentFlags & 0x08) != 0) note.accentuated = AccentuationType.Normal;
                    case "Tie":
                        if (c.get("origin").toLowerCase() == "true")
                        {
                            note.isTieOrigin = true;
                        }
                        if (c.get("destination").toLowerCase() == "true")
                        {
                            note.isTieDestination = true;
                        }
                    case "Vibrato":
                        switch(getValue(c))
                        {
                            case "Slight": note.vibrato = VibratoType.Slight;
                            case "Wide": note.vibrato = VibratoType.Wide;
                        }
                }
            }
		}
                
        _noteById.set(noteId, note);
    }
    
    private function parseNoteProperties(node:Xml, note:Note)
    {
        for (c in node)
		{
            if (c.nodeType == Xml.Element)
            {           
                switch(c.nodeName)
                {
                    case "Property":
                        parseNoteProperty(c, note);
                }
            }
		}
    }    
    private function parseNoteProperty(node:Xml, note:Note)
    {
        var isBended :Bool = false;
        var bendOrigin:BendPoint = null;
        var bendMiddle1:BendPoint = null;
        var bendMiddle2:BendPoint = null;
        var bendDestination:BendPoint = null;

        var name = node.get("name");
        switch(name)
        {
            case "String": 
                note.string = Std.parseInt(getValue(findChildElement(node, "String"))) + 1;
            case "Fret": 
                note.fret = Std.parseInt(getValue(findChildElement(node, "Fret")));
            // case "Tapped": 
            case "HarmonicType":
                var htype = findChildElement(node, "HType");
                if (htype != null)
                {
                    switch(getValue(htype))
                    {
                        case "NoHarmonic": note.harmonicType = HarmonicType.None;
                        case "Natural": note.harmonicType = HarmonicType.Natural;
                        case "Artificial": note.harmonicType = HarmonicType.Artificial;
                        case "Pinch": note.harmonicType = HarmonicType.Pinch;
                        case "Tap": note.harmonicType = HarmonicType.Tap;
                        case "Semi": note.harmonicType = HarmonicType.Semi;
                        case "Feedback": note.harmonicType = HarmonicType.Feedback;
                    }
                }
            case "HarmonicFret": 
                var hfret = findChildElement(node, "HFret");
                if (hfret != null)
                {
                    note.harmonicValue = Std.parseFloat(getValue(hfret));
                }
            // case "Muted": 
            case "PalmMuted": 
                if (findChildElement(node, "Enable") != null) note.isPalmMute = true;
            // case "Element": 
            // case "Variation": 
            // case "Tone": 
            case "Octave": 
                note.octave = Std.parseInt(getValue(findChildElement(node, "Number")));
            case "Bended": isBended = true;
            
            case "BendOriginValue": 
                if (bendOrigin == null) bendOrigin = new BendPoint();
                bendOrigin.value = Std.int(Std.parseFloat(getValue(findChildElement(node, "Float"))));
            case "BendOriginOffset":
                if (bendOrigin == null) bendOrigin = new BendPoint();
                bendOrigin.offset = Std.int(Std.parseFloat(getValue(findChildElement(node, "Float"))));

            case "BendMiddleValue":
                if (bendMiddle1 == null) bendMiddle1 = new BendPoint();
                if (bendMiddle2 == null) bendMiddle2 = new BendPoint();
                bendMiddle1.value = Std.int(Std.parseFloat(getValue(findChildElement(node, "Float"))));
                bendMiddle2.value = bendMiddle1.value;

            case "BendMiddleOffset1":
                if (bendMiddle1 == null) bendMiddle1 = new BendPoint();
                bendMiddle1.offset = Std.int(Std.parseFloat(getValue(findChildElement(node, "Float"))));
            case "BendMiddleOffset2":
                if (bendMiddle2 == null) bendMiddle2 = new BendPoint();
                bendMiddle2.offset = Std.int(Std.parseFloat(getValue(findChildElement(node, "Float"))));
            
            case "BendDestinationValue":
                if (bendDestination == null) bendDestination = new BendPoint();
                bendDestination.value = Std.int(Std.parseFloat(getValue(findChildElement(node, "Float"))));

            case "BendDestinationOffset":
                if (bendDestination == null) bendDestination = new BendPoint();
                bendDestination.offset = Std.int(Std.parseFloat(getValue(findChildElement(node, "Float"))));
                
            case "HopoOrigin": 
                if (findChildElement(node, "Enable") != null)
                    note.isHammerPullOrigin = true;
            case "HopoDestination": 
                // NOTE: gets automatically calculated 
                // if (findChildElement(node, "Enable") != null)
                //     note.isHammerPullDestination = true;
            case "Slide": 
                var slideFlags = Std.parseInt(getValue(findChildElement(node, "Flags")));
                if ( (slideFlags & 0x01) != 0) note.slideType = SlideType.Shift;
                if ( (slideFlags & 0x02) != 0) note.slideType = SlideType.Legato;
                if ( (slideFlags & 0x04) != 0) note.slideType = SlideType.OutDown;
                if ( (slideFlags & 0x08) != 0) note.slideType = SlideType.OutUp;
                if ( (slideFlags & 0x10) != 0) note.slideType = SlideType.IntoFromBelow;
                if ( (slideFlags & 0x20) != 0) note.slideType = SlideType.IntoFromAbove;
        }
        
        if (isBended && bendOrigin != null && bendDestination != null)
        {
            var bend = new Array<BendPoint>();
            bend.push(bendOrigin);
            if (bendMiddle1 != null) bend.push(bendMiddle1);
            if (bendMiddle2 != null) bend.push(bendMiddle2);
            bend.push(bendDestination);
            note.bendPoints = bend;
        }

    }
    
    private function parseRhythms(node:Xml)
    {
        for (c in node)
		{
            if (c.nodeType == Xml.Element)
            {           
                switch(c.nodeName)
                {
                    case "Rhythm": parseRhythm(c);
                }
            }
		}         
    }
    
    private function parseRhythm(node:Xml)
    {
        var rhythm = new GpxRhythm();
        var rhythmId = node.get("id");
        for (c in node)
		{
            if (c.nodeType == Xml.Element)
            {           
                switch(c.nodeName)
                {
                    case "NoteValue":
                        switch(getValue(c))
                        {
                            // case "Long":
                            // case "DoubleWhole":
                            case "Whole":
                                rhythm.value = Duration.Whole;
                            case "Half":
                                rhythm.value = Duration.Half;
                            case "Quarter":
                                rhythm.value = Duration.Quarter;
                            case "Eighth":
                                rhythm.value = Duration.Eighth;
                            case "16th":
                                rhythm.value = Duration.Sixteenth;
                            case "32nd":
                                rhythm.value = Duration.ThirtySecond;
                            case "64th":
                                rhythm.value = Duration.SixtyFourth;
                            // case "128th":
                            // case "256th":
                        }
                    case "PrimaryTuplet":
                        rhythm.tupletNumerator = Std.parseInt(c.get("num"));
                        rhythm.tupletDenominator = Std.parseInt(c.get("den"));
                    case "AugmentationDot":
                        rhythm.dots = Std.parseInt(c.get("count"));
                }
            }
		}
        
        _rhythmById.set(rhythmId, rhythm);
    }
    
    private function buildModel()
    {
        // build beats
        for (beatId in _beatById.keys())
        {
            var beat = _beatById.get(beatId);
            var rhythmId = _rhythmOfBeat.get(beatId);
            var rhythm = _rhythmById.get(rhythmId);
            
            // set beat duration
            beat.duration = rhythm.value;
            beat.dots = rhythm.dots;
            beat.tupletNumerator = rhythm.tupletNumerator;
            beat.tupletDenominator = rhythm.tupletDenominator;
            
            // add notes to beat
            if (_notesOfBeat.exists(beatId))
            {
                for (noteId in _notesOfBeat.get(beatId))
                {
                    if (noteId != InvalidId)
                    {
                        beat.addNote(_noteById.get(noteId));
                    }
                }
            }
        }

        // build voices
        for (voiceId in _voiceById.keys())
        {
            var voice = _voiceById.get(voiceId);
            if (_beatsOfVoice.exists(voiceId))
            {
                // add beats to voices
                for (beatId in _beatsOfVoice.get(voiceId))
                {
                    if (beatId != InvalidId)
                    {                        
                        // important! we clone the beat because beats get reused
                        // in gp6, our model needs to have unique beats.
                        voice.addBeat(_beatById.get(beatId).clone() );
                    }
                }
            }
        }
        
        // build bars
        for (barId in _barsById.keys())
        {
            var bar = _barsById.get(barId);
            if (_voicesOfBar.exists(barId))
            {
                // add voices to bars
                for (voiceId in _voicesOfBar.get(barId))
                {
                    if (voiceId != InvalidId)
                    {
                        bar.addVoice(_voiceById.get(voiceId));
                    }
                }
            }
        }

        // build tracks (not all, only those used by the score)
        var trackIndex = 0;
        for (trackId in _tracksMapping)
        {
            var track:Track = _tracksById.get(trackId);
            score.addTrack(track);
            
            // iterate all bar definitions for the masterbars
            // and add the correct bar to the track
            for (barIds in _barsOfMasterBar)
            {
                var barId = barIds[trackIndex];
                if (barId != InvalidId)
                {
                    track.addBar(_barsById.get(barId));
                }
            }
            
            trackIndex++;
        }
        
        // build automations
        for (barId in _automations.keys())
        {
            var bar:Bar = _barsById.get(barId);
            for (v in bar.voices)
            {
                if (v.beats.length > 0)
                {
                    for (automation in _automations.get(barId))
                    {
                        v.beats[0].automations.push(automation);
                    }
                }
            }
        }        
        
        // build score
        for (masterBar in _masterBars)
        {
            score.addMasterBar(masterBar);
        }
        if (_automations.exists("0")) // TODO find the correct first bar id
        {
            var automations = _automations.get("0");
            for (automation in automations)
            {
                if (automation.type == AutomationType.Tempo)
                {
                    score.tempo = Std.int(automation.value);
                    score.tempoLabel = automation.text;
                    break;
                }
            }
        }
    }        
}
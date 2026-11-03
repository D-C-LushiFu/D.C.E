package states.freeplayState.objects.replay;

/** Saved-record grades describe combo quality first, then miss count. */
class ReplayGrade
{
    public static function calculate(combo:String, misses:Int, hasJudgments:Bool = false,
        goods:Int = 0, bads:Int = 0, shits:Int = 0):String
    {
        if (misses == 0)
        {
            var normalized = combo == null ? '' : StringTools.trim(combo).toUpperCase();
            switch (normalized)
            {
                case 'SFC', 'PFC', 'MFC': return 'D.C.P';
                case 'GFC': return 'V';
                case 'FC': return 'S';
                default:
            }
            // New records can recover a missing combo label from their judgments.
            // Older records without judgment counts must not become perfect combos.
            if (hasJudgments)
            {
                if (bads > 0 || shits > 0) return 'S';
                if (goods > 0) return 'V';
                return 'D.C.P';
            }
        }
        if (misses >= 0 && misses < 5) return 'A';
        if (misses >= 0 && misses < 10) return 'B';
        if (misses >= 0 && misses < 15) return 'C';
        return 'D';
    }
}

require "TimedActions/ISBaseTimedAction"
require "SkillRecoveryJournalAction"

WriteSkillRecoveryJournal = SkillRecoveryJournalAction:derive("WriteSkillRecoveryJournal")

function WriteSkillRecoveryJournal:new(character, item, writingTool)
    return SkillRecoveryJournalAction:new(character, item, false, writingTool)
end

require "TimedActions/ISBaseTimedAction"
require "SkillRecoveryJournalAction"

WriteSkillRecoveryJournal = SkillRecoveryJournalAction:derive("WriteSkillRecoveryJournal")

function WriteSkillRecoveryJournal:new(character, item, writingTool)
    return SkillRecoveryJournalAction.newBase(self, character, item, false, writingTool)
end

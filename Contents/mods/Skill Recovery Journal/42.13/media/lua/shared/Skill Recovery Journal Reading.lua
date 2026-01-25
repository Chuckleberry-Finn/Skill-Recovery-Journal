require "TimedActions/ISBaseTimedAction"
require "SkillRecoveryJournalAction"

ReadSkillRecoveryJournal = SkillRecoveryJournalAction:derive("ReadSkillRecoveryJournal")

function ReadSkillRecoveryJournal:new(character, item)
    return SkillRecoveryJournalAction.newBase(self, character, item, true)
end

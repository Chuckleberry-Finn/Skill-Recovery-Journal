require "TimedActions/ISBaseTimedAction"
require "SkillRecoveryJournalAction"

ReadSkillRecoveryJournal = SkillRecoveryJournalAction:derive("ReadSkillRecoveryJournal")

function ReadSkillRecoveryJournal:new(character, item)
    return SkillRecoveryJournalAction:new(character, item, true)
end

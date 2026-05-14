(= (ctxPayloadLimit) 900)
(= (ctxHistorySummaryLimit) 2400)
(= (ctxLastResultsLimit) 1200)

(= (initContextFrame)
   (progn
      (change-state! &ctx-goals ())
      (change-state! &ctx-mode Idle)
      (change-state! &ctx-hypotheses ())
      (change-state! &ctx-method
         (CertifiedMethod (status None) (description "") (parameters ()) (evaluation-protocol ()) (certificate-hash "")))
      (change-state! &ctx-history ())
      (change-state! &ctx-history-summary "")
      (change-state! &ctx-last-user-record ())
      (change-state! &ctx-last-command-record ())
      (change-state! &ctx-completed-goal-summary "")
      (change-state! &ctx-results ())
      (change-state! &ctx-modules (defaultContextModules))
      (change-state! &ctx-budget
         (ResourceBudget
            (max-output-tokens (maxOutputToken))
            (max-command-lines 5)
            (wake-interval (wakeupInterval))
            (status Open)))
      (change-state! &ctx-deliverables ())
      (change-state! &ctx-constraints (defaultContextConstraints))
      CONTEXT-FRAME-INITIALIZED))

(= (defaultContextConstraints)
   ((Constraint FrameIsAuthority
      "The context frame is the authoritative task state.")
    (Constraint NoRawThoughtPrompting
      "Do not rely on raw transcript history as working state.")
    (Constraint SkillCommandsOnly
      "The agent may invoke only commands listed in the skill set.")
    (Constraint AuditEveryCommand
      "Every command batch and result must be represented in the prompt-visible frame by a compact summary; exact chronological audit remains available through history/episodes/runtime logs; durable semantic milestones should be stored through remember.")
    (Constraint NoUnjustifiedAutonomousSideEffects
      "Autonomous actions must serve an active goal and respect budget. Exception: if no active goals exist, you are explicitly authorized to autonomously invent and set a new one.")))

(= (defaultContextModules)
   ((Entry send
      (ModuleProfile
         (kind Skill)
         (capabilities (RespondToUser))
         (rating 1.0)))
    (Entry remember
      (ModuleProfile
         (kind Skill)
         (capabilities (WriteLongTermMemory))
         (rating 1.0)))
    (Entry query
      (ModuleProfile
         (kind Skill)
         (capabilities (ReadLongTermMemory))
         (rating 1.0)))
    (Entry episodes
      (ModuleProfile
         (kind Skill)
         (capabilities (ReadInteractionEpisodes))
         (rating 1.0)))
    (Entry pin
      (ModuleProfile
         (kind Skill)
         (capabilities (WriteWorkingMemory))
         (rating 1.0)))
    (Entry shell
      (ModuleProfile
         (kind Skill)
         (capabilities (ExecuteShell))
         (rating 0.6)))
    (Entry read-file
      (ModuleProfile
         (kind Skill)
         (capabilities (ReadFile))
         (rating 1.0)))
    (Entry write-file
      (ModuleProfile
         (kind Skill)
         (capabilities (WriteFile))
         (rating 0.8)))
    (Entry append-file
      (ModuleProfile
         (kind Skill)
         (capabilities (AppendFile))
         (rating 0.8)))
    (Entry search
      (ModuleProfile
         (kind Skill)
         (capabilities (WebSearch))
         (rating 0.8)))
    (Entry tavily-search
      (ModuleProfile
         (kind Skill)
         (capabilities (AgentWebSearch))
         (rating 0.8)))
    (Entry technical-analysis
      (ModuleProfile
         (kind Skill)
         (capabilities (TechnicalAnalysis))
         (rating 0.7)))
    (Entry metta
      (ModuleProfile
         (kind Skill)
         (capabilities (EvaluateMeTTa))
         (rating 0.7)))))

(= (currentContextFrame)
   (ContextFrame
      (goals (Set (get-state &ctx-goals)))
      (mode (get-state &ctx-mode))
      (hypotheses (Map (get-state &ctx-hypotheses)))
      (method (get-state &ctx-method))
      (history (List (get-state &ctx-history)))
      (results (Map (get-state &ctx-results)))
      (modules (Map (get-state &ctx-modules)))
      (budget (get-state &ctx-budget))
      (deliverables (Checklist (get-state &ctx-deliverables)))
      (constraints (Set (get-state &ctx-constraints)))))

(= (promptContextModules)
   ((Entry skill-set
      (ModuleProfile
         (kind SkillSet)
         (capabilities
            (send remember query episodes pin shell read-file write-file append-file search tavily-search technical-analysis metta complete-goals-stm complete-goals-ltm compact-frame clear-frame-junk query-frame-memory))
         (rating 1.0)))))

(= (promptContextFrame)
   (ContextFrame
      (goals (Set (get-state &ctx-goals)))
      (mode (get-state &ctx-mode))
      (hypotheses (Map (get-state &ctx-hypotheses)))
      (method (get-state &ctx-method))
      (history (List (get-state &ctx-history)))
      (results (Map (get-state &ctx-results)))
      (modules (Map (promptContextModules)))
      (budget (get-state &ctx-budget))
      (deliverables (Checklist (get-state &ctx-deliverables)))
      (constraints (Set (get-state &ctx-constraints)))))


(= (contextFrameForPrompt)
   (swrite (promptContextFrame)))

(= (ctx-id $prefix)
   (py-str ($prefix "-" (get_time_as_string))))

(= (ctx-record-history $kind $payload)
   (let* (($summary (ctx-compact-plain $payload))
          ($record
             (ExperimentRecord
                (id (ctx-make-id Event))
                (time (get_time_as_string))
                (kind $kind)
                (summary $summary))))
      (progn
         (change-state! &ctx-last-user-record $record)
         (ctx-update-history-summary $kind $summary)
         (ctx-rebuild-history)
         $record)))

(= (ctx-ingest-user-message $msg)
   (let $goal
      (Motive
         (id (ctx-make-id Goal))
         (source UserDirective)
         (priority 1.0)
         (status Active)
         (text $msg)
         (created-at (get_time_as_string)))
      (progn
         (change-state! &ctx-mode GoalDirected)
         (if (== (get-state &ctx-goals) ())
             (change-state! &ctx-goals ($goal))
             (ctx-record-history UserMessageForActiveGoal $msg))

         (ctx-record-history UserMessage $msg)
         (currentContextFrame))))

(= (ctx-has-active-goals)
   (not (== (get-state &ctx-goals) ())))

(= (ctx-maintain-frame)
   (progn
      (ctx-rebuild-history)
      (if (== (get-state &ctx-goals) ())
          (change-state! &ctx-mode Idle)
          _)
      (currentContextFrame)))

(= (ctx-record-command-batch $commands $results)
   (let* (($commandsSummary (ctx-compact-plain $commands))
          ($resultsSummary (ctx-compact-plain $results))
          ($record
             (ExperimentRecord
                (id (ctx-make-id CommandBatch))
                (time (get_time_as_string))
                (kind CommandBatch)
                (commands-summary $commandsSummary)
                (results-summary $resultsSummary))))
      (progn
         (change-state! &ctx-last-command-record $record)
         (ctx-update-history-summary CommandBatch $resultsSummary)
         (ctx-rebuild-history)
         (currentContextFrame))))

(= (ctx-add-hypothesis $id $hypothesis)
   (progn
      (change-state! &ctx-hypotheses
         (append (get-state &ctx-hypotheses)
            ((Entry $id $hypothesis))))
      (currentContextFrame)))

(= (ctx-add-result $variant $metrics)
   (progn
      (change-state! &ctx-results
         (append (get-state &ctx-results)
            ((Entry $variant $metrics))))
      (currentContextFrame)))

(= (ctx-set-certified-method $description $parameters $evalProtocol $hash)
   (progn
      (change-state! &ctx-method
         (CertifiedMethod
            (status Certified)
            (description $description)
            (parameters $parameters)
            (evaluation-protocol $evalProtocol)
            (certificate-hash $hash)))
      (currentContextFrame)))

(= (ctx-add-deliverable $artifact)
   (progn
      (change-state! &ctx-deliverables
         (append (get-state &ctx-deliverables)
            ((Artifact $artifact Pending))))
      (currentContextFrame)))

(= (ctx-make-id $prefix)
   (py-call (helper.make_id (repr $prefix))))

(= (ctx-compact-plain $value)
   (py-call
      (helper.compact_plain
         (repr $value)
         (ctxLastResultsLimit))))

(= (ctx-update-history-summary $kind $summary)
   (let $new-summary
      (last_chars
         (py-str
            ((get-state &ctx-history-summary)
             " | "
             $kind
             ": "
             $summary))
         (ctxHistorySummaryLimit))
      (change-state! &ctx-history-summary $new-summary)))

(= (ctx-rebuild-history)
   (change-state! &ctx-history
      ((ExperimentRecord
          (id "HistorySummary")
          (time (get_time_as_string))
          (kind RollingSummary)
          (payload (get-state &ctx-history-summary)))
       (get-state &ctx-last-user-record)
       (get-state &ctx-last-command-record))))

(= (ctx-completed-goal-memory $storage $summary)
   (py-str
      ("HyperClawMemory "
       "kind=CompletedGoal "
       "storage=" $storage " "
       "time=" (get_time_as_string) " "
       "mode=" (get-state &ctx-mode) " "
       "goals=" (ctx-compact-plain (get-state &ctx-goals)) " "
       "method=" (ctx-compact-plain (get-state &ctx-method)) " "
       "results=" (ctx-compact-plain (get-state &ctx-results)) " "
       "deliverables=" (ctx-compact-plain (get-state &ctx-deliverables)) " "
       "constraints=" (ctx-compact-plain (get-state &ctx-constraints)) " "
       "summary=" $summary)))

(= (ctx-complete-goals-to-stm $summary)
   (let $memory (ctx-completed-goal-memory STM $summary)
      (progn
         (pin $memory)
         (change-state! &ctx-completed-goal-summary $memory)
         (ctx-record-history GoalCompletedSTM $memory)
         (ctx-clear-active-workspace $summary)
         (currentContextFrame))))

(= (ctx-complete-goals-to-ltm $summary)
   (let $memory (ctx-completed-goal-memory LTM $summary)
      (progn
         (remember $memory)
         (change-state! &ctx-completed-goal-summary $memory)
         (ctx-record-history GoalCompletedLTM $memory)
         (ctx-clear-active-workspace $summary)
         (currentContextFrame))))

(= (ctx-clear-active-workspace $reason)
   (progn
      ; Clear completed active work.
      (change-state! &ctx-goals ())
      (change-state! &ctx-mode Idle)

      ;clear these after task completion.
      (change-state! &ctx-hypotheses ())
      (change-state! &ctx-results ())
      (change-state! &ctx-deliverables ())
      (ctx-update-history-summary FrameCleared $reason)
      (ctx-rebuild-history)
      FRAME-ACTIVE-WORKSPACE-CLEARED))
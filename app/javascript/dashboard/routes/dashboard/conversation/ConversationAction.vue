<!-- eslint-disable vue/v-slot-style -->
<script>
import { computed } from 'vue';
import { mapGetters } from 'vuex';
import { useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useConnectaAssignableAgents } from 'dashboard/composables/useConnectaAssignableAgents';
import { getAgentsByUpdatedPresence } from 'dashboard/helper/agentHelper';
import { sortAgentsByName } from 'dashboard/helper/connectaAssignableAgents';
import ContactDetailsItem from './ContactDetailsItem.vue';
import MultiselectDropdown from 'shared/components/ui/MultiselectDropdown.vue';
import ConversationLabels from './labels/LabelBox.vue';
import { CONVERSATION_PRIORITY } from '../../../../shared/constants/messages';
import { CONVERSATION_EVENTS } from '../../../helper/AnalyticsHelper/events';
import { useAlert, useTrack, useAssignmentError } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    ContactDetailsItem,
    MultiselectDropdown,
    ConversationLabels,
    NextButton,
  },
  props: {
    conversationId: {
      type: [Number, String],
      required: true,
    },
  },
  setup() {
    const store = useStore();
    const { t } = useI18n();
    const currentChatId = computed(() => store.getters.getSelectedChat?.id);
    const { flatAgents } = useConnectaAssignableAgents(currentChatId);

    // Department-aware sidebar list: only agents returned by the new
    // endpoint (already filtered server-side), alphabetical, with the
    // current user's live presence. Grouping is skipped here because
    // MultiselectDropdown has no section headers; the flat sorted list is
    // the requirement.
    const agentsList = computed(() => {
      const currentChat = store.getters.getSelectedChat;
      const currentUser = store.getters.getCurrentUser;
      const currentAccountId = store.getters.getCurrentAccountId;
      const agents = (flatAgents.value || []).map(agent =>
        !agent.name && agent.assignee_type === 'AgentBot'
          ? { ...agent, name: '-' }
          : agent
      );
      const withPresence = getAgentsByUpdatedPresence(
        agents,
        currentUser,
        currentAccountId
      );
      const sorted = sortAgentsByName(withPresence);
      const isAgentSelected = !!currentChat?.meta?.assignee;
      if (!isAgentSelected) return sorted;
      return [
        {
          confirmed: true,
          name: t('AGENT_MGMT.MULTI_SELECTOR.LIST.NONE') || 'None',
          id: 0,
          role: 'agent',
          account_id: 0,
          email: 'None',
          connectaOrgUnitId: null,
        },
        ...sorted,
      ];
    });

    return {
      agentsList,
    };
  },
  data() {
    return {
      priorityOptions: [
        {
          id: null,
          name: this.$t('CONVERSATION.PRIORITY.OPTIONS.NONE'),
          icon: 'i-woot-priority-empty',
        },
        {
          id: CONVERSATION_PRIORITY.URGENT,
          name: this.$t('CONVERSATION.PRIORITY.OPTIONS.URGENT'),
          icon: 'i-woot-priority-urgent',
        },
        {
          id: CONVERSATION_PRIORITY.HIGH,
          name: this.$t('CONVERSATION.PRIORITY.OPTIONS.HIGH'),
          icon: 'i-woot-priority-high',
        },
        {
          id: CONVERSATION_PRIORITY.MEDIUM,
          name: this.$t('CONVERSATION.PRIORITY.OPTIONS.MEDIUM'),
          icon: 'i-woot-priority-medium',
        },
        {
          id: CONVERSATION_PRIORITY.LOW,
          name: this.$t('CONVERSATION.PRIORITY.OPTIONS.LOW'),
          icon: 'i-woot-priority-low',
        },
      ],
    };
  },
  computed: {
    ...mapGetters({
      currentChat: 'getSelectedChat',
      currentUser: 'getCurrentUser',
      teams: 'teams/getTeams',
    }),
    hasAnAssignedTeam() {
      return !!this.currentChat?.meta?.team;
    },
    teamsList() {
      if (this.hasAnAssignedTeam) {
        return [
          { id: 0, name: this.$t('TEAMS_SETTINGS.LIST.NONE') },
          ...this.teams,
        ];
      }
      return this.teams;
    },
    assignedAgent: {
      get() {
        const assignee = this.currentChat.meta.assignee;
        return (
          assignee && {
            ...assignee,
            assignee_type: this.currentChat.meta.assignee_type || 'User',
          }
        );
      },
      async set(agent) {
        const assigneeType = agent ? agent.assignee_type || 'User' : null;
        try {
          await this.$store.dispatch('assignAgent', {
            conversationId: this.currentChat.id,
            assignee: agent,
            assigneeType,
            // Cross-department move: only present when the agent comes from
            // another department's group.
            connectaOrgUnitId: agent?.connectaOrgUnitId ?? null,
          });
          useAlert(this.$t('CONVERSATION.CHANGE_AGENT'));
        } catch (error) {
          useAssignmentError(
            error,
            this.$t('CONVERSATION.CHANGE_AGENT_FAILED')
          );
        }
      },
    },
    assignedTeam: {
      get() {
        return this.currentChat.meta.team;
      },
      async set(team) {
        try {
          await this.$store.dispatch('assignTeam', {
            conversationId: this.currentChat.id,
            team,
          });
          useAlert(this.$t('CONVERSATION.CHANGE_TEAM'));
        } catch (error) {
          useAssignmentError(error, this.$t('CONVERSATION.CHANGE_TEAM_FAILED'));
        }
      },
    },
    assignedPriority: {
      get() {
        const selectedOption = this.priorityOptions.find(
          opt => opt.id === this.currentChat.priority
        );

        return selectedOption || this.priorityOptions[0];
      },
      set(priorityItem) {
        const conversationId = this.currentChat.id;
        const oldValue = this.currentChat?.priority;
        const priority = priorityItem.id;

        this.$store.dispatch('setCurrentChatPriority', {
          priority,
          conversationId,
        });
        this.$store
          .dispatch('assignPriority', { conversationId, priority })
          .then(() => {
            useTrack(CONVERSATION_EVENTS.CHANGE_PRIORITY, {
              oldValue,
              newValue: priority,
              from: 'Conversation Sidebar',
            });
            useAlert(
              this.$t('CONVERSATION.PRIORITY.CHANGE_PRIORITY.SUCCESSFUL', {
                priority: priorityItem.name,
                conversationId,
              })
            );
          });
      },
    },
    showSelfAssign() {
      if (!this.assignedAgent) {
        return true;
      }
      if (
        this.assignedAgent.id !== this.currentUser.id ||
        (this.assignedAgent.assignee_type || 'User') !== 'User'
      ) {
        return true;
      }
      return false;
    },
  },
  methods: {
    onSelfAssign() {
      const {
        account_id,
        availability_status,
        available_name,
        email,
        id,
        name,
        role,
        avatar_url,
      } = this.currentUser;
      const selfAssign = {
        account_id,
        availability_status,
        available_name,
        email,
        id,
        name,
        role,
        thumbnail: avatar_url,
      };
      this.assignedAgent = selfAssign;
    },
    onClickAssignAgent(selectedItem) {
      if (
        this.assignedAgent?.id === selectedItem.id &&
        (this.assignedAgent?.assignee_type || 'User') ===
          (selectedItem.assignee_type || 'User')
      ) {
        this.assignedAgent = null;
      } else {
        this.assignedAgent = selectedItem;
      }
    },

    onClickAssignTeam(selectedItemTeam) {
      if (this.assignedTeam && this.assignedTeam.id === selectedItemTeam.id) {
        this.assignedTeam = null;
      } else {
        this.assignedTeam = selectedItemTeam;
      }
    },

    onClickAssignPriority(selectedPriorityItem) {
      const isSamePriority =
        this.assignedPriority &&
        this.assignedPriority.id === selectedPriorityItem.id;

      this.assignedPriority = isSamePriority
        ? this.priorityOptions[0]
        : selectedPriorityItem;
    },
  },
};
</script>

<template>
  <div>
    <div>
      <ContactDetailsItem
        compact
        :title="$t('CONVERSATION_SIDEBAR.ASSIGNEE_LABEL')"
      >
        <template #button>
          <NextButton
            v-if="showSelfAssign"
            link
            xs
            icon="i-lucide-arrow-right"
            class="!gap-1"
            :label="$t('CONVERSATION_SIDEBAR.SELF_ASSIGN')"
            @click="onSelfAssign"
          />
        </template>
      </ContactDetailsItem>
      <MultiselectDropdown
        :options="agentsList"
        :selected-item="assignedAgent"
        :multiselector-title="$t('AGENT_MGMT.MULTI_SELECTOR.TITLE.AGENT')"
        :multiselector-placeholder="$t('AGENT_MGMT.MULTI_SELECTOR.PLACEHOLDER')"
        :no-search-result="
          $t('AGENT_MGMT.MULTI_SELECTOR.SEARCH.NO_RESULTS.AGENT')
        "
        :input-placeholder="
          $t('AGENT_MGMT.MULTI_SELECTOR.SEARCH.PLACEHOLDER.AGENT')
        "
        @select="onClickAssignAgent"
      />
    </div>
    <div>
      <ContactDetailsItem
        compact
        :title="$t('CONVERSATION_SIDEBAR.TEAM_LABEL')"
      />
      <MultiselectDropdown
        :options="teamsList"
        :selected-item="assignedTeam"
        show-emoji-icon
        :multiselector-title="$t('AGENT_MGMT.MULTI_SELECTOR.TITLE.TEAM')"
        :multiselector-placeholder="$t('AGENT_MGMT.MULTI_SELECTOR.PLACEHOLDER')"
        :no-search-result="
          $t('AGENT_MGMT.MULTI_SELECTOR.SEARCH.NO_RESULTS.TEAM')
        "
        :input-placeholder="
          $t('AGENT_MGMT.MULTI_SELECTOR.SEARCH.PLACEHOLDER.TEAM')
        "
        @select="onClickAssignTeam"
      />
    </div>
    <div>
      <ContactDetailsItem compact :title="$t('CONVERSATION.PRIORITY.TITLE')" />
      <MultiselectDropdown
        :options="priorityOptions"
        :selected-item="assignedPriority"
        :multiselector-title="$t('CONVERSATION.PRIORITY.TITLE')"
        :multiselector-placeholder="
          $t('CONVERSATION.PRIORITY.CHANGE_PRIORITY.SELECT_PLACEHOLDER')
        "
        :no-search-result="
          $t('CONVERSATION.PRIORITY.CHANGE_PRIORITY.NO_RESULTS')
        "
        :input-placeholder="
          $t('CONVERSATION.PRIORITY.CHANGE_PRIORITY.INPUT_PLACEHOLDER')
        "
        @select="onClickAssignPriority"
      />
    </div>
    <ContactDetailsItem
      compact
      :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONVERSATION_LABELS')"
    />
    <ConversationLabels :conversation-id="conversationId" />
  </div>
</template>

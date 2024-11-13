#!/usr/bin/python
import time

from bioblend.galaxy import GalaxyInstance
gi = GalaxyInstance('http://galaxytest', key='fakekey')
gi.histories.create_history()
# print(gi.tools.get_tool_panel())
history = gi.histories.get_most_recently_used_history()
# print(dir(history))
history_id = history['id']
# print(history_id)
tool_output = gi.tools.run_tool(
    history_id=history_id,
    tool_id="outputhostname",
    tool_inputs={}
)

# print(tool_output)

# loop until job finish timeout is 30sec
result = "noresult"
for x in range(0, 30):
    time.sleep(1)
    show_history = gi.histories.show_history(history_id)
    if len(show_history['state_ids']['ok']) > 0:
        dataset_id = show_history['state_ids']['ok'][0]
        dataset = gi.datasets.show_dataset(dataset_id)
        result = dataset['peek']
        break
print(result)

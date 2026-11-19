{% test unique_claim_segment(model) %}

select claim_id, claim_segment
from {{ model }}
group by claim_id, claim_segment
having count(*) > 1

{% endtest %}

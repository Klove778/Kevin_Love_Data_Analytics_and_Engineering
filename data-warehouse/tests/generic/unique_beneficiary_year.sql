{% test unique_beneficiary_year(model) %}

select beneficiary_id, reporting_year
from {{ model }}
group by beneficiary_id, reporting_year
having count(*) > 1

{% endtest %}

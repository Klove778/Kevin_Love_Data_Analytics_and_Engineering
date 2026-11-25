"""Reproduce the four published holdout rankings at 485 slots."""

from argparse import ArgumentParser
from pathlib import Path

from holdout_evaluation import get_features, read_input, train


def esrd_features(row):
    return (get_features(row)[0], float(row['esrd_flag'] == 'Y'))


def compare(data):
    top = [row for row in data if row['prior_top'] == '1']
    training = [row for row in top if int(row['split_hash'][:2], 16) < 179]
    testing = [row for row in top if int(row['split_hash'][:2], 16) >= 179]
    mix = train(training)
    esrd_fit = train(training, feature_extractor=esrd_features)
    positives = sum(int(row['subsequent_top']) for row in testing)
    capacity = 485
    assert (len(training), len(testing), positives) == (4430, 1938, 579)

    methods = (
        ('Total prior-year spending', lambda row: float(row['paid'])),
        ('Total spending plus ESRD', esrd_fit),
        ('Outpatient plus carrier spending', lambda row: float(row['op_paid']) + float(row['car_paid'])),
        ('Full service-mix model', mix),
    )
    results = []
    reference = None
    for index, (name, score) in enumerate(methods, start=1):
        ranked = sorted(testing, key=lambda row: (-score(row), row['split_hash']))
        reviewed = {row['split_hash']: int(row['subsequent_top']) for row in ranked[:capacity]}
        correct = sum(reviewed.values())
        if reference is None:
            reference = reviewed
        results.append(dict(
            method_order=index, method=name, correct_predictions=correct,
            review_capacity=capacity, precision_pct=round(100*correct/capacity, 2),
            recall_pct=round(100*correct/positives, 2), actual_positives=positives,
            evaluated_beneficiaries=len(testing), training_beneficiaries=len(training),
            extra_correct_vs_total_spending=correct-sum(reference.values()),
            new_correct_vs_total_spending=sum(reviewed[key] for key in reviewed.keys()-reference.keys()),
            lost_correct_vs_total_spending=sum(reference[key] for key in reference.keys()-reviewed.keys()),
            evaluation='Original held-out beneficiaries', baseline_year=2008, outcome_year=2009,
            evaluation_period='2008 to 2009',
        ))
    assert [r['correct_predictions'] for r in results] == [163, 243, 260, 268]
    assert (results[-1]['new_correct_vs_total_spending'],
            results[-1]['lost_correct_vs_total_spending']) == (164, 59)
    outpatient = sorted(testing, key=lambda row: (-float(row['op_paid']), row['split_hash']))
    assert sum(int(row['subsequent_top']) for row in outpatient[:capacity]) == 242
    return results


if __name__ == '__main__':
    parser = ArgumentParser(description=__doc__)
    parser.add_argument('input_csv', type=Path)
    for result in compare(read_input(parser.parse_args().input_csv)):
        print(result)

from argparse import ArgumentParser
import csv
import hashlib
import math
import random
from operator import mul
from pathlib import Path
from statistics import mean, pstdev

CONDITIONS = (
    'alzheimers_or_related_disorder', 'heart_failure', 'chronic_kidney_disease', 'cancer',
    'copd', 'depression', 'diabetes', 'ischemic_heart_disease', 'osteoporosis',
    'rheumatoid_arthritis_or_osteoarthritis', 'stroke_or_tia',
)
CODE_FEATURES = (
    'op_dialysis', 'op_renal', 'op_renal_therapy', 'op_oncology',
    'dialysis_months', 'oncology_months', 'other_renal', 'other_dialysis',
)
COMPLEXITY = (
    'non-inpatient dollars', 'non-inpatient minus peak quarter', 'mix', 'mix + conditions',
    'mix + recurrence', 'mix + conditions + codes', 'mix + recurrence + conditions + codes',
    'split ESRD, mix + conditions', 'split ESRD, all features',
)
PENALTY = 12.0
FRACTION = 0.25

def get_row(row):
    def number(name):
        return float(row[name])
    paid = number('paid')
    ip, op, car = (number(name) for name in ('ip_paid', 'op_paid', 'car_paid'))
    counts = tuple(number(name) for name in ('ip_n', 'op_n', 'car_n'))
    def ratio(amount, total):
        return amount / total if total > 0 else 0.0
    mix = (math.log1p(paid), ip / paid, op / paid, car / paid,
           *(math.log1p(n) for n in counts), float(counts[0] == 0))
    recurrence = (
        *(number(name) for name in ('op_paid_months', 'car_paid_months',
                                    'op_paid_quarters', 'car_paid_quarters')),
        *(ratio(number(name), total) for name, total in (
            ('max_op_claim', op), ('max_car_claim', car),
            ('max_op_quarter', op), ('max_car_quarter', car), ('op_late', op), ('car_late', car)
        )),
    )
    flags = tuple(number(name) for name in CONDITIONS)
    esrd = int(row['esrd'])
    condition = (float(esrd), *flags)
    codes = tuple(number(name) for name in CODE_FEATURES)
    return dict(
        key=row['split_hash'], y=int(row['y']), esrd=esrd, paid=paid, nonip=op + car,
        nonip_repeat=op + car - number('max_op_quarter') - number('max_car_quarter'),
        features={
            'mix': mix, 'mix + conditions': mix + condition,
            'mix + recurrence': mix + recurrence,
            'mix + conditions + codes': mix + condition + codes,
            'mix + recurrence + conditions + codes': mix + recurrence + condition + codes,
            'split ESRD, mix + conditions': mix + flags,
            'split ESRD, all features': mix + recurrence + flags + codes,
        }
    )

def dot(x, y):
    return sum(map(mul, x, y))

def sigmoid(t):
    if t >= 0:
        return 1.0 / (1.0 + math.exp(-t))
    a = math.exp(t)
    return a / (1.0 + a)

def logistic(training, name):
    values = [row['features'][name] for row in training]
    centers = [mean(col) for col in zip(*values)]
    scales = [pstdev(col) or 1.0 for col in zip(*values)]

    def transform(raw):
        return (1.0,) + tuple((v - m) / s for v, m, s in zip(raw, centers, scales))

    rows = list(map(transform, values))
    cols = tuple(zip(*rows))
    outcome = [row['y'] for row in training]
    n = len(outcome)

    def value_gradient(beta):
        logit = [dot(row, beta) for row in rows]
        loss = sum(max(t, 0.0) - y*t + math.log1p(math.exp(-abs(t)))
                   for y, t in zip(outcome, logit))
        residual = [sigmoid(t) - y for y, t in zip(outcome, logit)]
        grad = [dot(col, residual) / n for col in cols]
        for j in range(1, len(beta)):
            grad[j] += PENALTY * beta[j] / n
        return (loss + 0.5 * PENALTY * dot(beta[1:], beta[1:])) / n, grad

    beta = [0.0 for _ in cols]
    beta[0] = math.log(sum(outcome) / (n - sum(outcome)))
    loss, grad = value_gradient(beta)
    memory = []
    for _ in range(100):
        if max(map(abs, grad)) < 0.00003:
            break
        direction = grad[:]
        alphas = []
        for delta, curvature, inverse in reversed(memory):
            alpha = inverse * dot(delta, direction)
            alphas.append(alpha)
            direction = [q - alpha*c for q, c in zip(direction, curvature)]
        if memory:
            delta, curvature, _ = memory[-1]
            scale = dot(delta, curvature) / dot(curvature, curvature)
            direction = [scale*q for q in direction]
        for (delta, curvature, inverse), alpha in zip(memory, reversed(alphas)):
            correction = alpha - inverse * dot(curvature, direction)
            direction = [q + correction*d for q, d in zip(direction, delta)]
        step = 1.0
        slope = dot(direction, grad)
        while True:
            next_beta = [b - step*d for b, d in zip(beta, direction)]
            next_loss, next_grad = value_gradient(next_beta)
            if next_loss <= loss - 0.0001 * step * slope:
                break
            step *= 0.5
            if step < 1e-8:
                raise RuntimeError(f'Line search failed for {name}')
        delta = [b - a for a, b in zip(beta, next_beta)]
        curvature = [b - a for a, b in zip(grad, next_grad)]
        inner = dot(delta, curvature)
        if inner > 1e-12:
            memory = (memory + [(delta, curvature, 1.0 / inner)])[-7:]
        beta, loss, grad = next_beta, next_loss, next_grad
    else:
        raise RuntimeError(f'Fit failed to converge for {name}')

    return lambda row: dot(transform(row['features'][name]), beta)

def scores(name, training, validation):
    simple = {'total dollars': 'paid', 'non-inpatient dollars': 'nonip',
              'non-inpatient minus peak quarter': 'nonip_repeat'}
    if name in simple:
        return [row[simple[name]] for row in validation]
    if name.startswith('split ESRD'):
        group_models = {g: logistic([r for r in training if r['esrd'] == g], name) for g in (0, 1)}
        # Log odds are comparable across strata under the model's own calibration.
        return [group_models[row['esrd']](row) for row in validation]
    model = logistic(training, name)
    return [model(row) for row in validation]

def splits(rows, folds, salt):
    strata = {}
    for i, row in enumerate(rows):
        strata.setdefault((row['esrd'], row['y']), []).append(i)
    buckets = [[] for _ in range(folds)]
    offset = 0
    for stratum in sorted(strata):
        indices = sorted(strata[stratum], key=lambda i: hashlib.sha256(
            (rows[i]['key'] + salt).encode()).digest())
        for j, index in enumerate(indices):
            buckets[(j + offset) % folds].append(index)
        offset += len(indices)
    for indices in buckets:
        held = set(indices)
        yield ([row for i, row in enumerate(rows) if i not in held],
               [rows[i] for i in sorted(indices)])

def review_budgets(sizes, fraction):
    wanted = [n * fraction for n in sizes]
    budgets = [math.floor(n) for n in wanted]
    leftover = math.floor(sum(wanted)+0.5) - sum(budgets)
    for i in sorted(range(len(sizes)), key=lambda i: (-(wanted[i] - budgets[i]), i))[:leftover]:
        budgets[i] += 1
    return budgets

def selected_indices(rows, prediction, capacity, indices=None):
    use = range(len(rows)) if indices is None else indices
    return sorted(use, key=lambda i: (-prediction[i], rows[i]['key']))[:capacity]

def hits(rows, score, capacity):
    return sum(rows[i]['y'] for i in selected_indices(rows, score, capacity))

def pick(training, fold_id):
    partitions = list(splits(training, 3, f'inner-{fold_id}'))
    budgets = review_budgets([len(val) for _, val in partitions], FRACTION)
    totals = dict.fromkeys(COMPLEXITY, 0)
    for (train, val), budget in zip(partitions, budgets):
        for method in COMPLEXITY:
            totals[method] += hits(val, scores(method, train, val), budget)
    # Prefer the simpler rule when it is within 2 percentage points of the best
    # inner validation precision. This is a decision preference, not a test.
    high = max(totals.values())
    close = 0.02 * sum(budgets)
    selected = next(name for name in COMPLEXITY if totals[name] >= high-close)
    return selected, max(COMPLEXITY, key=totals.get), totals

def wilson(count, n):
    p = count / n
    scale = 1 + 1.96**2/n
    center = (p + 1.96**2/(2*n))/scale
    span = 1.96 * math.sqrt(p*(1-p)/n+1.96**2/(4*n*n))/scale
    return round(100*(center-span),2), round(100*(center+span),2)

def summarize(results, names, budgets):
    n_positive = sum(row['y'] for rows, _ in results for row in rows)
    print('Budget', sum(budgets), 'actual positives', n_positive, flush=True)
    baseline = 'non-inpatient dollars'
    summaries = []
    for order, name in enumerate(names, start=1):
        fold_metrics, gained, lost = [], 0, 0
        by_group = [[0, 0, 0], [0, 0, 0]]
        for (rows, pred), budget in zip(results, budgets):
            ref = set(selected_indices(rows, pred[baseline], budget))
            choice = selected_indices(rows, pred[name], budget)
            fold_metrics.append(sum(rows[i]['y'] for i in choice))
            chosen = set(choice)
            gained += sum(rows[i]['y'] for i in chosen - ref)
            lost += sum(rows[i]['y'] for i in ref - chosen)
            for i, row in enumerate(rows):
                group = by_group[row['esrd']]
                group[0] += int(i in chosen)
                group[1] += row['y'] * int(i in chosen)
                group[2] += row['y']
        correct = sum(fold_metrics)
        precision_low, precision_high = wilson(correct, sum(budgets))
        recall_low, recall_high = wilson(correct, n_positive)
        summaries.append(dict(
            method_order=order, method=name, correct_predictions=correct,
            review_capacity=sum(budgets), precision_pct=round(100*correct/sum(budgets),2),
            recall_pct=round(100*correct/n_positive,2), actual_positives=n_positive,
            evaluated_beneficiaries=sum(len(rows) for rows, _ in results),
            precision_ci_low_pct=precision_low, precision_ci_high_pct=precision_high,
            recall_ci_low_pct=recall_low, recall_ci_high_pct=recall_high,
            new_correct_vs_outpatient_carrier=gained, lost_correct_vs_outpatient_carrier=lost,
            evaluation='Original training cohort, five outer folds',
            baseline_year=2008, outcome_year=2009, evaluation_period='2008 to 2009',
        ))
        print(name, 'hits',correct, 'precision',round(100*correct/sum(budgets),2),
              'precision Wilson',wilson(correct,sum(budgets)),
              'recall',round(100*correct/n_positive,2),'recall Wilson',wilson(correct,n_positive),
              'gained/lost vs non-inpatient',gained,lost,'fold hits',fold_metrics,
              'subgroup slots/hits/positives',by_group,flush=True)

    return summaries


def paired_bootstrap(results, budgets, names, repetitions=1000):
    rng = random.Random(81723)
    baseline = 'non-inpatient dollars'
    # Pre-sort both score lists in each fold. Rank bootstrap copies by original
    # rank, retaining each row's multiplicity and the same capacity in every draw.
    ordered = []
    for rows, prediction in results:
        order = {name: selected_indices(rows, prediction[name], len(rows))
                 for name in (baseline, *names)}
        ordered.append((order, [row['y'] for row in rows]))
    total_budget = sum(budgets)
    draws = {name: [] for name in names}
    for _ in range(repetitions):
        totals = dict.fromkeys((baseline, *names), 0)
        for (order, y), budget in zip(ordered, budgets):
            multiplicity = [0]*len(y)
            for i in rng.choices(range(len(y)), k=len(y)):
                multiplicity[i] += 1
            for name, ranking in order.items():
                left = budget
                count = 0
                for i in ranking:
                    copies = min(left, multiplicity[i])
                    count += y[i]*copies
                    left -= copies
                    if not left:
                        break
                totals[name] += count
        for name in names:
            draws[name].append(100*(totals[name]-totals[baseline])/total_budget)
    intervals = {}
    for name, values in draws.items():
        values.sort()
        intervals[name] = (round(values[24],2),round(values[974],2))
        print('paired bootstrap delta pp vs non-inpatient',name,*intervals[name],flush=True)
    return intervals

def by_group_at_equal_slots(results, budgets, names):
    base = 'non-inpatient dollars'
    for name in names:
        group_stats = [[0, 0], [0, 0]]
        for (rows, prediction), budget in zip(results, budgets):
            chosen = selected_indices(rows, prediction[base], budget)
            for g in (0, 1):
                slots = sum(rows[i]['esrd'] == g for i in chosen)
                eligible = [i for i, row in enumerate(rows) if row['esrd'] == g]
                group_stats[g][0] += slots
                group_stats[g][1] += sum(rows[i]['y'] for i in
                    selected_indices(rows, prediction[name], slots, eligible))
        print('equal subgroup slots/hits',name,group_stats,flush=True)

def evaluate(input_path):
    with input_path.open(newline='') as file:
        data = [get_row(row) for row in csv.DictReader(file)]
    assert len(data) == len({row['key'] for row in data}) == 4430
    assert all(int(row['key'][:2], 16) < 179 for row in data)
    assert sum(row['y'] for row in data) == 1366
    outer = list(splits(data, 5, 'outer-prior-high-cost'))
    budgets = review_budgets([len(val) for _, val in outer], FRACTION)
    results = []
    names = ('total dollars', *COMPLEXITY)
    for i, (train, val) in enumerate(outer):
        pick_simple, pick_best, totals = pick(train, i)
        pred = {name: scores(name, train, val) for name in names}
        pred['nested selected, prefer simple'] = pred[pick_simple]
        pred['nested selected, highest inner yield'] = pred[pick_best]
        results.append((val, pred))
        print('fold',i,'train',len(train),'validation',len(val),'inner selection',
              (pick_simple, pick_best), totals,flush=True)
    full_names = (*names, 'nested selected, prefer simple', 'nested selected, highest inner yield')
    summaries = summarize(results, full_names, budgets)
    intervals = paired_bootstrap(results, budgets, full_names[2:])
    by_group_at_equal_slots(results, budgets, full_names)
    reference = summaries[1]['correct_predictions']
    for row in summaries:
        row['extra_correct_vs_outpatient_carrier'] = row['correct_predictions'] - reference
        row['precision_delta_vs_outpatient_carrier_pp'] = round(
            100 * (row['correct_predictions'] - reference) / row['review_capacity'], 2)
        low, high = intervals.get(row['method'], (None, None))
        row['delta_ci_low_pp'] = low
        row['delta_ci_high_pp'] = high
    assert [row['correct_predictions'] for row in summaries] == [
        430, 647, 646, 651, 648, 658, 647, 655, 645, 659, 641, 651,
    ]
    return summaries


if __name__ == '__main__':
    parser = ArgumentParser(description='Reproduce nested cross-validation on the original training cohort.')
    parser.add_argument('input_csv', type=Path)
    evaluate(parser.parse_args().input_csv)
